import Testing
import Foundation
@testable import StarHubTHCore

/// X103-B — la corbeille des mods supprimés : nommage, dépôt, remise en
/// désactivé, purge. Chaque règle ici est un engagement d'interface : la
/// corbeille vit DANS `Mods/` sous le préfixe que le scanner saute déjà,
/// « remettre » ne peut jamais écraser, la quarantaine du réparateur (même
/// préfixe, sans marqueur) n'est pas de la corbeille, et aucune purge n'est
/// automatique.
struct ModTrashTests {

    private func makeTempModsDir() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("modtrash-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// Le projet rend `String.appendingPathComponent` indisponible (forcer le
    /// cast `NSString`) : ce petit constructeur évite de caster à chaque ligne.
    private func path(_ base: String, _ parts: String...) -> String {
        parts.reduce(base) { ($0 as NSString).appendingPathComponent($1) }
    }

    /// Crée un événement de corbeille **utilisateur** : dossier + marqueur.
    @discardableResult
    private func makeEvent(_ mods: String, _ name: String) throws -> String {
        let dir = path(mods, name)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try ModTrash.markEvent(eventDir: dir)
        return dir
    }

    // MARK: - Nommage

    @Test func stampIsChronologicalAndPosix() {
        let date = Date(timeIntervalSince1970: 1_780_000_000) // 2026-06-02 ~03:46 UTC
        let stamp = ModTrash.makeStamp(date)
        // yyyyMMdd_HHmmss : huit chiffres, le soulignement, six chiffres.
        #expect(stamp.count == 15)
        #expect(stamp.contains("_"))
        let digits = stamp.filter(\.isNumber)
        #expect(digits.count == 14)
    }

    @Test func trashFolderCarriesTheScannerSkippedPrefix() {
        let name = ModTrash.trashFolderName(stamp: "20260909_101112")
        #expect(name.hasPrefix("_Trash_"))
        #expect(ModTrash.isTrashFolder(name))
        #expect(!ModTrash.isTrashFolder("CJBCheats"))
        // Un mod légitime dont le nom contiendrait « Trash » ailleurs ne
        // doit pas être avalé par le garde.
        #expect(!ModTrash.isTrashFolder("MyTrashFinder"))
    }

    // MARK: - Déposer

    @Test func destinationUsesTheLogicalLeafAndCountsCollisions() {
        let eventDir = makeTempModsDir().appending("/_Trash_20260909_101112")
        try? FileManager.default.createDirectory(atPath: eventDir, withIntermediateDirectories: true)

        let first = ModTrash.destination(eventDir: eventDir, logicalFolderName: "CJBCheats")
        #expect(first == path(eventDir, "CJBCheats"))

        // Un homonyme supprimé dans le même événement se décale, jamais
        // n'écrase.
        try? FileManager.default.createDirectory(atPath: first, withIntermediateDirectories: true)
        let second = ModTrash.destination(eventDir: eventDir, logicalFolderName: "CJBCheats")
        #expect(second.hasSuffix("CJBCheats_1"))
        #expect(second != first)
    }

    // MARK: - Remettre

    @Test func restoreForcesTheDisabledDotOnTheLeaf() {
        let mods = makeTempModsDir()
        let dest = ModTrash.restoreDestination(modsPath: mods,
                                               entryRelativePath: "CJBCheats",
                                               stamp: "20260909_101112")
        #expect(dest == path(mods, ".CJBCheats"))
    }

    @Test func restoreNeverOverwritesAnExistingFolder() {
        let mods = makeTempModsDir()
        let existing = path(mods, ".CJBCheats")
        try? FileManager.default.createDirectory(atPath: existing, withIntermediateDirectories: true)

        let dest = ModTrash.restoreDestination(modsPath: mods,
                                               entryRelativePath: "CJBCheats",
                                               stamp: "20260909_101112")
        #expect(dest.hasSuffix(".CJBCheats_20260909_101112_1"))
        #expect(dest != existing)
    }

    @Test func restoreKeepsAnAlreadyDisabledLeafAsIs() {
        let mods = makeTempModsDir()
        let dest = ModTrash.restoreDestination(modsPath: mods,
                                               entryRelativePath: ".AlreadyPaused",
                                               stamp: "20260909_101112")
        #expect(dest == path(mods, ".AlreadyPaused"))
    }

    // MARK: - Marqueur (quarantaine du réparateur ≠ corbeille utilisateur)

    @Test func unmarkedEventsAreNotListed() throws {
        let mods = makeTempModsDir()
        // Un dossier `_Trash_*` sans marqueur = quarantaine du réparateur :
        // la corbeille utilisateur ne le liste pas.
        let repairer = path(mods, "_Trash_20260909_090000")
        try FileManager.default.createDirectory(atPath: repairer, withIntermediateDirectories: true)
        try "x".write(to: URL(fileURLWithPath: path(repairer, "Junk")),
                      atomically: true, encoding: .utf8)
        #expect(ModTrash.events(modsPath: mods).isEmpty)

        let user = path(mods, "_Trash_20260909_101112")
        try FileManager.default.createDirectory(atPath: user, withIntermediateDirectories: true)
        try ModTrash.markEvent(eventDir: user)
        try "x".write(to: URL(fileURLWithPath: path(user, "MyMod")),
                      atomically: true, encoding: .utf8)
        let events = ModTrash.events(modsPath: mods)
        #expect(events.count == 1)
        #expect(events.first?.entries == ["MyMod"])
    }

    @Test func purgeAllSkipsRepairerQuarantine() throws {
        let mods = makeTempModsDir()
        let repairer = path(mods, "_Trash_20260909_090000")
        try FileManager.default.createDirectory(atPath: repairer, withIntermediateDirectories: true)
        try makeEvent(mods, "_Trash_20260909_101112")

        let removed = try ModTrash.purgeAll(modsPath: mods)
        #expect(removed == 1)
        // La quarantaine du réparateur survit au « vider la corbeille ».
        #expect(FileManager.default.fileExists(atPath: repairer))
        #expect(!FileManager.default.fileExists(
            atPath: path(mods, "_Trash_20260909_101112")))
    }

    @Test func purgeEntryRefusesAnUnmarkedEvent() throws {
        let mods = makeTempModsDir()
        let event = path(mods, "_Trash_20260909_090000")
        try FileManager.default.createDirectory(atPath: event, withIntermediateDirectories: true)
        #expect(throws: (Error).self) {
            try ModTrash.purgeEntry(modsPath: mods, event: "_Trash_20260909_090000",
                                    entry: "Junk")
        }
    }

    @Test func discardEventKeepsTheEventWhileTheMarkerHoldsIt() throws {
        let mods = makeTempModsDir()
        let event = "_Trash_20260909_101112"
        let dir = try makeEvent(mods, event)
        // Le marqueur seul ne retient pas l'événement : vidé, il disparaît.
        ModTrash.discardEventIfEmpty(modsPath: mods, event: event)
        #expect(!FileManager.default.fileExists(atPath: dir))
    }

    // MARK: - Lister

    @Test func eventsListNewestFirstWithTopLevelEntries() throws {
        let mods = makeTempModsDir()
        try makeEvent(mods, "_Trash_20260901_090000")
        try makeEvent(mods, "_Trash_20260909_101112")
        try "x".write(to: URL(fileURLWithPath: path(mods, "_Trash_20260901_090000", "OldMod")),
                      atomically: true, encoding: .utf8)
        try "x".write(to: URL(fileURLWithPath: path(mods, "_Trash_20260909_101112", "NewMod")),
                      atomically: true, encoding: .utf8)

        let events = ModTrash.events(modsPath: mods)
        #expect(events.count == 2)
        #expect(events.first?.folderName == "_Trash_20260909_101112")
        #expect(events.first?.entries == ["NewMod"])
        #expect(events.last?.entries == ["OldMod"])
        // La date lue dans le nom est exposée pour l'affichage.
        #expect(events.first?.date != nil)
    }

    @Test func emptyEventsAreNotListed() throws {
        let mods = makeTempModsDir()
        try makeEvent(mods, "_Trash_20260909_101112")
        #expect(ModTrash.events(modsPath: mods).isEmpty)
    }

    // MARK: - Purger

    @Test func purgeEntryRemovesTheEntryThenTheEmptyEvent() throws {
        let mods = makeTempModsDir()
        let event = "_Trash_20260909_101112"
        let entry = path(mods, event, "CJBCheats")
        try FileManager.default.createDirectory(atPath: entry, withIntermediateDirectories: true)
        try ModTrash.markEvent(eventDir: path(mods, event))

        try ModTrash.purgeEntry(modsPath: mods, event: event, entry: "CJBCheats")

        #expect(!FileManager.default.fileExists(atPath: entry))
        // L'événement vidé ne laisse pas de dossier fantôme.
        #expect(!FileManager.default.fileExists(atPath: path(mods, event)))
    }

    @Test func purgeEntryRefusesToEscapeTheEvent() throws {
        let mods = makeTempModsDir()
        // Le nom d'événement est un garde : autre chose que `_Trash_*` est
        // refusé avant même de construire un chemin.
        #expect(throws: (Error).self) {
            try ModTrash.purgeEntry(modsPath: mods, event: "CJBCheats", entry: "x")
        }
    }

    @Test func purgeAllRemovesEveryEventAndCountsThem() throws {
        let mods = makeTempModsDir()
        try makeEvent(mods, "_Trash_20260901_090000")
        try makeEvent(mods, "_Trash_20260909_101112")
        let removed = try ModTrash.purgeAll(modsPath: mods)
        #expect(removed == 2)
        #expect(ModTrash.events(modsPath: mods).isEmpty)
    }
}
