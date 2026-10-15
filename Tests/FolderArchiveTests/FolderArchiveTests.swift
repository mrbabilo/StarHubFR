import Testing
import Foundation
@testable import StarHubTHCore

/// Les lignes viennent de `/usr/bin/zip -r -db -dc` réellement lancé le
/// 2026-10-15 (macOS 26, Zip 3.0) : comptes « fait/reste », octets en unités
/// de 1 024, une décimale sous 10.
struct FolderArchiveProgressTests {
    @Test func aRealZipLineIsRead() throws {
        let p = try #require(FolderArchive.progress(fromLine: "  4/  3 [1.7M/ 11M]   adding: c/huge.bin (deflated 0%)"))
        #expect(p.entriesDone == 4)
        #expect(p.entriesTotal == 7)
        #expect(p.bytesDone == Int64(1.7 * 1_048_576))
        #expect(p.bytesTotal == Int64(1.7 * 1_048_576) + 11 * 1_048_576)
    }

    @Test func plainBytesAndKilobytesAreRead() throws {
        let p = try #require(FolderArchive.progress(fromLine: "  2/  5 [292K/ 13M]   adding: c/ (stored 0%)"))
        #expect(p.bytesDone == 292 * 1024)
        let q = try #require(FolderArchive.progress(fromLine: "  6/  1 [ 13M/   3]   adding: b.json (stored 0%)"))
        #expect(q.bytesTotal == 13 * 1_048_576 + 3)
    }

    @Test func gigabytesAreRead() {
        #expect(FolderArchive.bytes(fromZipSize: "1.4G") == Int64(1.4 * 1_073_741_824))
        #expect(FolderArchive.bytes(fromZipSize: "12G") == Int64(12) * 1_073_741_824)
    }

    /// Un nom de fichier accentué ou à crochets ne doit pas tromper la lecture.
    @Test func aFileNameWithBracketsDoesNotConfuseTheReader() throws {
        let p = try #require(FolderArchive.progress(fromLine: "  5/  2 [ 13M/   9]   adding: [SMI] Café [v2]/a.json (stored 0%)"))
        #expect(p.entriesDone == 5)
    }

    @Test func otherLinesAreIgnored() {
        #expect(FolderArchive.progress(fromLine: "zip warning: name not matched: x") == nil)
        #expect(FolderArchive.progress(fromLine: "") == nil)
    }

    @Test func theFractionFollowsBytesAndStaysInBounds() throws {
        let p = try #require(FolderArchive.progress(fromLine: "  0/  7 [   0/ 13M]   adding: a/ (stored 0%)"))
        #expect(p.fraction == 0)
        let empty = FolderArchive.Progress(entriesDone: 0, entriesTotal: 0, bytesDone: 0, bytesTotal: 0)
        #expect(empty.fraction == 0)
    }
}

struct FolderArchivePlanTests {
    /// 5 % de marge, jamais moins de 200 Mo : une archive ne dépasse pas sa
    /// source de plus que ses en-têtes, mais un disque plein à 100 % casse tout.
    @Test func theRequiredSpaceHasAMargin() {
        #expect(FolderArchive.requiredBytes(sourceBytes: 14_000_000_000) == 14_700_000_000)
        #expect(FolderArchive.requiredBytes(sourceBytes: 50_000_000) == 250_000_000)
    }

    @Test func enoughSpaceIsJudgedOnTheRequiredBytes() {
        #expect(FolderArchive.hasEnoughSpace(sourceBytes: 14_000_000_000, available: 14_800_000_000))
        #expect(!FolderArchive.hasEnoughSpace(sourceBytes: 14_000_000_000, available: 14_500_000_000))
        // Le système ne dit pas l'espace libre : on ne bloque pas sur une inconnue.
        #expect(FolderArchive.hasEnoughSpace(sourceBytes: 14_000_000_000, available: nil))
    }

    @Test func theDurationIsEstimatedFromTheThroughput() {
        #expect(FolderArchive.estimatedSeconds(bytes: 13_000_000_000, bytesPerSecond: 13_000_000) == 1000)
        // Un débit absurde retombe sur le défaut plutôt que de promettre l'instantané.
        #expect(FolderArchive.estimatedSeconds(bytes: 13_000_000, bytesPerSecond: 0)
                == 13_000_000 / FolderArchive.defaultBytesPerSecond)
    }

    @Test func theRemainingTimeComesFromTheLiveRate() throws {
        let p = FolderArchive.Progress(entriesDone: 10, entriesTotal: 40, bytesDone: 1_000, bytesTotal: 4_000)
        #expect(FolderArchive.remainingSeconds(progress: p, elapsed: 60) == 180)
        // Rien de lu encore : aucune estimation plutôt qu'une division par zéro.
        let start = FolderArchive.Progress(entriesDone: 0, entriesTotal: 40, bytesDone: 0, bytesTotal: 4_000)
        #expect(FolderArchive.remainingSeconds(progress: start, elapsed: 5) == nil)
    }

    @Test func theArchiveNameIsSortableAndLocaleFree() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 7, second: 3))!
        #expect(FolderArchive.archiveName(prefix: "StardewMods", date: date, calendar: calendar)
                == "StardewMods_2026-10-05_09-07-03.zip")
    }

    @Test func aDestinationInsideTheSourceIsSeen() {
        let mods = URL(fileURLWithPath: "/G/Mods", isDirectory: true)
        #expect(FolderArchive.destination(mods, isInside: mods))
        #expect(FolderArchive.destination(mods.appendingPathComponent("Backups"), isInside: mods))
        #expect(FolderArchive.destination(URL(fileURLWithPath: "/G/Mods/./x/.."), isInside: mods))
        // Voisin au même préfixe de nom : pas dedans.
        #expect(!FolderArchive.destination(URL(fileURLWithPath: "/G/Mods2"), isInside: mods))
        #expect(!FolderArchive.destination(URL(fileURLWithPath: "/G"), isInside: mods))
    }

    /// Le temporaire de `zip` va dans un dossier caché (`-b`) ; les formats déjà
    /// compressés sont stockés tels quels (`-n`).
    @Test func theZipArgumentsHideTheTemporaryFile() {
        let args = FolderArchive.zipArguments(archive: URL(fileURLWithPath: "/D/a.zip"),
                                              temporaryFolder: URL(fileURLWithPath: "/D/.tmp"))
        #expect(args.first == "-r")
        #expect(args.contains("-db") && args.contains("-dc"))
        let b = args.firstIndex(of: "-b")
        #expect(b.map { args[$0 + 1] } == "/D/.tmp")
        let n = args.firstIndex(of: "-n")
        #expect(n.map { args[$0 + 1].contains(".png") } == true)
        #expect(args.suffix(2) == ["/D/a.zip", "."])
    }
}

/// Un vrai `zip`, sur un dossier jetable : l'archive finit au bon endroit, et
/// une annulation ne laisse rien derrière elle.
@MainActor
struct FolderArchiveStoreTests {
    private func makeSource(bytes: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("A"), withIntermediateDirectories: true)
        // Octets aléatoires : `zip` ne peut pas les réduire, il les lit en vrai.
        // Découpés en fichiers de 10 Mo au plus, pour que l'avancement bouge.
        let chunk = 10_000_000
        var random = Data(count: min(bytes, chunk))
        random.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        var written = 0
        var index = 0
        while written < bytes {
            let size = min(chunk, bytes - written)
            try random.prefix(size).write(to: root.appendingPathComponent("A/data-\(index).bin"))
            written += size
            index += 1
        }
        try Data("{}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        return root
    }

    private func makeDestination() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-dst-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Les sources pèsent jusqu'à 300 Mo : rien ne doit rester dans le
    /// dossier temporaire après le test.
    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "FolderArchiveStoreTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    /// Attend hors de `#expect` : la macro fige l'autoclosure (piège X106).
    private func waitUntilDone(_ store: FolderArchiveStore, seconds: Double = 30) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !store.isRunning { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @Test func anArchiveLandsWhereAskedAndNothingElseIsLeft() async throws {
        let source = try makeSource(bytes: 200_000)
        defer { remove(source) }
        let destination = try makeDestination()
        defer { remove(destination) }
        let store = FolderArchiveStore(defaults: isolatedDefaults())
        store.start(kind: .mods, source: source, destinationFolder: destination,
                    archiveName: "t.zip", sourceBytes: 200_000)
        await waitUntilDone(store)
        guard case .finished(let url, _, _) = store.phase else {
            Issue.record("phase \(store.phase)"); return
        }
        #expect(url == destination.appendingPathComponent("t.zip"))
        let left = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(left == ["t.zip"])
        #expect(store.lastDestination(for: .mods)?.path == destination.path)
    }

    @Test func cancellingRemovesThePartialArchive() async throws {
        let source = try makeSource(bytes: 60_000_000)
        defer { remove(source) }
        let destination = try makeDestination()
        defer { remove(destination) }
        let store = FolderArchiveStore(defaults: isolatedDefaults())
        store.start(kind: .saves, source: source, destinationFolder: destination,
                    archiveName: "t.zip", sourceBytes: 60_000_000)
        store.cancel()
        await waitUntilDone(store)
        #expect(store.phase == .cancelled)
        let left = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(left.isEmpty)
    }

    /// Un mod en pause est un dossier `.X` dans `Mods/` — 809 des ~1 030
    /// entrées du parc réel le 2026-10-15. La sauvegarde doit les emporter.
    @Test func pausedModsAreInTheArchive() async throws {
        let source = try makeSource(bytes: 1_000)
        defer { remove(source) }
        let paused = source.appendingPathComponent(".Paused Mod")
        try FileManager.default.createDirectory(at: paused, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: paused.appendingPathComponent("manifest.json"))
        let destination = try makeDestination()
        defer { remove(destination) }
        let store = FolderArchiveStore(defaults: isolatedDefaults())
        store.start(kind: .mods, source: source, destinationFolder: destination,
                    archiveName: "t.zip", sourceBytes: 1_000)
        await waitUntilDone(store)
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        listing.arguments = ["-1", destination.appendingPathComponent("t.zip").path]
        let output = Pipe()
        listing.standardOutput = output
        try listing.run()
        let names = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        listing.waitUntilExit()
        #expect(names.contains(".Paused Mod/manifest.json"))
        #expect(names.contains("A/data-0.bin"))
    }

    /// Le vrai cas : `zip` tourne déjà, son temporaire existe. Le tuer le
    /// laisse derrière lui — c'est au store de le retirer.
    @Test func cancellingARunningZipRemovesItsTemporary() async throws {
        let source = try makeSource(bytes: 300_000_000)
        defer { remove(source) }
        let destination = try makeDestination()
        defer { remove(destination) }
        let store = FolderArchiveStore(defaults: isolatedDefaults())
        store.start(kind: .mods, source: source, destinationFolder: destination,
                    archiveName: "t.zip", sourceBytes: 300_000_000)
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if case .running(let progress?, _) = store.phase, progress.entriesDone > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        store.cancel()
        await waitUntilDone(store)
        #expect(store.phase == .cancelled)
        let left = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(left.isEmpty)
    }

    /// Archiver `Mods/` dans `Mods/Backups` ferait naître un dossier caché —
    /// un « mod en pause » — dans la source, que `zip` lirait en cours d'écriture.
    @Test func aDestinationInsideTheSourceIsRefused() async throws {
        let source = try makeSource(bytes: 1_000)
        defer { remove(source) }
        let inside = source.appendingPathComponent("A", isDirectory: true)
        let store = FolderArchiveStore(defaults: isolatedDefaults())
        store.start(kind: .mods, source: source, destinationFolder: inside,
                    archiveName: "t.zip", sourceBytes: 1_000)
        guard case .failed = store.phase else { Issue.record("phase \(store.phase)"); return }
        let left = try FileManager.default.contentsOfDirectory(atPath: inside.path)
        #expect(left == ["data-0.bin"])
    }

    @Test func aMissingSourceFailsWithoutLeavingAnything() async throws {
        let destination = try makeDestination()
        defer { remove(destination) }
        let store = FolderArchiveStore(defaults: isolatedDefaults())
        store.start(kind: .mods, source: destination.appendingPathComponent("absent"),
                    destinationFolder: destination, archiveName: "t.zip", sourceBytes: 0)
        await waitUntilDone(store)
        guard case .failed = store.phase else { Issue.record("phase \(store.phase)"); return }
        let left = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(left.isEmpty)
    }

    /// Seule une archive assez grosse renseigne le débit : celle de quelques
    /// Mo de parties mesure surtout le lancement de `zip`.
    @Test func aFinishedArchiveTeachesTheThroughput() async throws {
        let source = try makeSource(bytes: 2_000_000)
        defer { remove(source) }
        let destination = try makeDestination()
        defer { remove(destination) }
        let defaults = isolatedDefaults()
        let store = FolderArchiveStore(defaults: defaults, minimumLearningBytes: 1)
        #expect(store.bytesPerSecond == FolderArchive.defaultBytesPerSecond)
        store.start(kind: .mods, source: source, destinationFolder: destination,
                    archiveName: "t.zip", sourceBytes: 2_000_000)
        await waitUntilDone(store)
        #expect(FolderArchiveStore(defaults: defaults).bytesPerSecond != FolderArchive.defaultBytesPerSecond)
    }

    @Test func aSmallArchiveDoesNotTeachTheThroughput() async throws {
        let source = try makeSource(bytes: 2_000_000)
        defer { remove(source) }
        let destination = try makeDestination()
        defer { remove(destination) }
        let defaults = isolatedDefaults()
        let store = FolderArchiveStore(defaults: defaults)
        store.start(kind: .saves, source: source, destinationFolder: destination,
                    archiveName: "t.zip", sourceBytes: 2_000_000)
        await waitUntilDone(store)
        #expect(FolderArchiveStore(defaults: defaults).bytesPerSecond == FolderArchive.defaultBytesPerSecond)
    }
}
