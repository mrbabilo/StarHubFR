import Foundation
import Testing
@testable import StarHubTHCore

/// Le fournisseur réel du tri, de bout en bout sur des dossiers temporaires
/// et un faux Nexus : journal local, manifeste récent, dépôts de l'app,
/// identification du fichier Nexus par l'empreinte de l'archive.
struct TriageSessionTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TriageSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func write(_ text: String, _ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func sha(_ text: String) throws -> String {
        try ModFolderHasher.sha256(of: write(text, "hash/\(UUID().uuidString)"))
    }

    private func mod(nexusId: String = "123") -> ModItem {
        ModItem(uniqueId: "a.sample", name: "Sample", folderName: "SampleMod", version: "1.0.0",
                author: "A", description: "", nexusUrl: "", nexusModId: nexusId, isEnabled: true,
                dependencies: [], children: nil, isGroup: false)
    }

    /// `modFiles` avec un fichier récent en 1.0.0, et son manifeste.
    private func nexus(manifest files: [String: String], archiveSHA: String) -> NexusFileManifestFetcher.Transport {
        let entries = files.map { #"{"file_path":"\#($0.key)","file_hashes":{"SHA256":"\#($0.value)"}}"# }
        let manifest = #"{"archive":{"hashes":{"SHA256":"\#(archiveSHA)"}},"files":["#
            + entries.joined(separator: ",") + "]}"
        let listing = #"{"data":{"modFiles":[{"fileId":77,"version":"1.0.0","uri":"aa/bb/cc/aabbcc00-0000-4000-8000-000000000077","date":1700000000}]}}"#
        return { request in
            let url = request.url?.absoluteString ?? ""
            if url.hasSuffix("/v2/graphql") { return .init(body: Data(listing.utf8), status: 200) }
            return .init(body: Data(manifest.utf8), status: 200)
        }
    }

    @Test func endToEndOnTemporaryFolders() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try write("m", "Installed/manifest.json")
        _ = try write("old", "Installed/a.png")
        _ = try write("ghost", "Installed/assets/ghost.png")
        _ = try write("mine", "Installed/i18n/fr.json")
        _ = try write("bag", "Installed/assets/Modded Bags/bag.json")
        _ = try write("m", "New/manifest.json")
        _ = try write("new", "New/a.png")
        let archive = try write("the zip", "archive.zip")
        let registry = InstalledTranslationRegistry(byHost: [
            "SampleMod": InstalledTranslation(hostFolderName: "SampleMod", nexusModId: 5,
                                              nexusName: "FR", version: "1", updatedAt: nil,
                                              installedAt: Date(), files: ["i18n/fr.json"]),
        ])
        let provider = UpdateTriageSession.provider(
            translations: registry, customNexusIds: [:], archive: archive,
            historyDirectory: root.appendingPathComponent("History"), cacheDirectory: nil,
            transport: nexus(manifest: ["Sample/manifest.json": try sha("m"),
                                        "Sample/a.png": try sha("old"),
                                        "Sample/assets/ghost.png": try sha("ghost")],
                             archiveSHA: try ModFolderHasher.sha256(of: archive)))
        let plan = try #require(provider.plan(mod(), root.appendingPathComponent("Installed"),
                                              root.appendingPathComponent("New")))
        #expect(plan.decisions["assets/ghost.png"] == .removeGhost)
        #expect(plan.decisions["a.png"] == .takeNew)
        #expect(plan.decisions["i18n/fr.json"] == .keepDeposit)
        #expect(plan.decisions["assets/Modded Bags/bag.json"] == .keepLocal(authorNowShips: false))
        #expect(plan.sourceFileId == 77)
        #expect(!plan.report.nexusIncomplete)
    }

    /// L'archive se lit quand le tri planifie — sur la file de fond de
    /// l'installateur —, pas quand le fournisseur est construit, sur le fil
    /// principal : Wildroot pèse 55 Mo, et une installation neuve n'en a pas
    /// besoin du tout.
    @Test func theArchiveIsReadWhenPlanningNotWhenBuilding() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try write("old", "Installed/a.png")
        _ = try write("new", "New/a.png")
        let archive = root.appendingPathComponent("later.zip")
        let provider = UpdateTriageSession.provider(
            translations: InstalledTranslationRegistry(), customNexusIds: [:], archive: archive,
            historyDirectory: nil, cacheDirectory: nil,
            transport: nexus(manifest: ["Sample/manifest.json": "m"], archiveSHA: try sha("the zip")))
        try Data("the zip".utf8).write(to: archive)
        let plan = try #require(provider.plan(mod(), root.appendingPathComponent("Installed"),
                                              root.appendingPathComponent("New")))
        #expect(plan.sourceFileId == 77)
    }

    /// Un mod sans id Nexus : aucune requête, le journal local seul.
    @Test func withoutNexusIdNothingIsAsked() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try write("x", "Installed/a.png")
        _ = try write("y", "New/a.png")
        let asked = Counter()
        let provider = UpdateTriageSession.provider(
            translations: InstalledTranslationRegistry(), customNexusIds: [:], archive: nil,
            historyDirectory: root.appendingPathComponent("History"), cacheDirectory: nil,
            transport: { _ in asked.increment(); return .init(body: nil, status: nil) })
        let plan = try #require(provider.plan(mod(nexusId: ""), root.appendingPathComponent("Installed"),
                                              root.appendingPathComponent("New")))
        #expect(asked.value == 0)
        #expect(plan.decisions["a.png"] == .replaceUnverified)
    }

    /// L'id saisi à la main l'emporte sur celui du manifeste.
    @Test func aCustomNexusIdIsUsed() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try write("x", "Installed/a.png")
        _ = try write("y", "New/a.png")
        let asked = Counter()
        let provider = UpdateTriageSession.provider(
            translations: InstalledTranslationRegistry(), customNexusIds: ["SampleMod": "456"],
            archive: nil, historyDirectory: nil, cacheDirectory: nil,
            transport: { _ in asked.increment(); return .init(body: nil, status: nil) })
        let plan = try #require(provider.plan(mod(nexusId: ""), root.appendingPathComponent("Installed"),
                                              root.appendingPathComponent("New")))
        #expect(asked.value == 1)
        #expect(plan.report.nexusIncomplete)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }
}
