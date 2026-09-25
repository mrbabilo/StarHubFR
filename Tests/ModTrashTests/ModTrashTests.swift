import Testing
import Foundation
@testable import StarHubTHCore

/// X103-B — la corbeille des mods supprimés : nommage, dépôt, remise en
/// désactivé, purge. Chaque règle ici est un engagement d'interface : la
/// corbeille vit HORS de `Mods/` (X115, SMAPI lisait chaque événement comme
/// un mod sans manifeste), « remettre » ne peut jamais écraser, la quarantaine du réparateur (même
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

    /// Un dossier de jeu jetable : `gameDir` et son `Mods/`.
    private func makeGame() throws -> (gameDir: String, mods: String) {
        let gameDir = makeTempModsDir()
        let mods = path(gameDir, "Mods")
        try FileManager.default.createDirectory(atPath: mods, withIntermediateDirectories: true)
        return (gameDir, mods)
    }

    /// Crée un événement de corbeille **utilisateur** : dossier + marqueur.
    @discardableResult
    private func makeEvent(_ mods: String, _ name: String) throws -> String {
        let dir = path(mods, name)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try ModTrash.markEvent(eventDir: dir)
        return dir
    }

    // MARK: - X110 — un mod en lecture seule

    /// `.[CP] Toothless Pet` sur le parc réel : dossier, `assets/` et `i18n/`
    /// en 0555. Le déplacer en corbeille marche (seul le parent doit être
    /// inscriptible) ; l'effacer ensuite échouait en `Code=513`, et « Vider la
    /// corbeille » s'arrêtait au premier événement.
    private func makeReadOnlyEntry(_ mods: String, event: String, entry: String) throws {
        let ev = try makeEvent(mods, event)
        let modDir = path(ev, entry)
        let sub = path(modDir, "i18n")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        try "{}".write(toFile: path(sub, "default.json"), atomically: true, encoding: .utf8)
        for dir in [sub, modDir] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir)
        }
    }

    @Test func aReadOnlyEntryIsPurged() throws {
        let mods = makeTempModsDir()
        try makeReadOnlyEntry(mods, event: "_Trash_20260924_120000", entry: "Pet")
        try ModTrash.purgeEntry(trashRoot: mods, event: "_Trash_20260924_120000", entry: "Pet")
        #expect(!FileManager.default.fileExists(atPath: path(mods, "_Trash_20260924_120000", "Pet")))
    }

    @Test func emptyingTheTrashGetsPastAReadOnlyEntry() throws {
        let mods = makeTempModsDir()
        try makeReadOnlyEntry(mods, event: "_Trash_20260924_120000", entry: "Pet")
        try makeEvent(mods, "_Trash_20260924_130000")
        #expect(try ModTrash.purgeAll(trashRoot: mods) == 2)
        #expect(ModTrash.events(trashRoot: mods).isEmpty)
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
        #expect(ModTrash.events(trashRoot: mods).isEmpty)

        let user = path(mods, "_Trash_20260909_101112")
        try FileManager.default.createDirectory(atPath: user, withIntermediateDirectories: true)
        try ModTrash.markEvent(eventDir: user)
        try "x".write(to: URL(fileURLWithPath: path(user, "MyMod")),
                      atomically: true, encoding: .utf8)
        let events = ModTrash.events(trashRoot: mods)
        #expect(events.count == 1)
        #expect(events.first?.entries == ["MyMod"])
    }

    @Test func purgeAllSkipsRepairerQuarantine() throws {
        let mods = makeTempModsDir()
        let repairer = path(mods, "_Trash_20260909_090000")
        try FileManager.default.createDirectory(atPath: repairer, withIntermediateDirectories: true)
        try makeEvent(mods, "_Trash_20260909_101112")

        let removed = try ModTrash.purgeAll(trashRoot: mods)
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
            try ModTrash.purgeEntry(trashRoot: mods, event: "_Trash_20260909_090000",
                                    entry: "Junk")
        }
    }

    @Test func discardEventKeepsTheEventWhileTheMarkerHoldsIt() throws {
        let mods = makeTempModsDir()
        let event = "_Trash_20260909_101112"
        let dir = try makeEvent(mods, event)
        // Le marqueur seul ne retient pas l'événement : vidé, il disparaît.
        ModTrash.discardEventIfEmpty(trashRoot: mods, event: event)
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

        let events = ModTrash.events(trashRoot: mods)
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
        #expect(ModTrash.events(trashRoot: mods).isEmpty)
    }

    // MARK: - Purger

    @Test func purgeEntryRemovesTheEntryThenTheEmptyEvent() throws {
        let mods = makeTempModsDir()
        let event = "_Trash_20260909_101112"
        let entry = path(mods, event, "CJBCheats")
        try FileManager.default.createDirectory(atPath: entry, withIntermediateDirectories: true)
        try ModTrash.markEvent(eventDir: path(mods, event))

        try ModTrash.purgeEntry(trashRoot: mods, event: event, entry: "CJBCheats")

        #expect(!FileManager.default.fileExists(atPath: entry))
        // L'événement vidé ne laisse pas de dossier fantôme.
        #expect(!FileManager.default.fileExists(atPath: path(mods, event)))
    }

    @Test func purgeEntryRefusesToEscapeTheEvent() throws {
        let mods = makeTempModsDir()
        // Le nom d'événement est un garde : autre chose que `_Trash_*` est
        // refusé avant même de construire un chemin.
        #expect(throws: (Error).self) {
            try ModTrash.purgeEntry(trashRoot: mods, event: "CJBCheats", entry: "x")
        }
    }

    @Test func purgeAllRemovesEveryEventAndCountsThem() throws {
        let mods = makeTempModsDir()
        try makeEvent(mods, "_Trash_20260901_090000")
        try makeEvent(mods, "_Trash_20260909_101112")
        let removed = try ModTrash.purgeAll(trashRoot: mods)
        #expect(removed == 2)
        #expect(ModTrash.events(trashRoot: mods).isEmpty)
    }

    // MARK: - Déposer un lot (« Vider les mods désactivés »)

    /// Le vidage des mods en pause emportait 721 dossiers du parc par
    /// `removeItem` définitif, seul chemin de suppression resté hors
    /// corbeille. Un lot = un seul événement, restaurable d'un bloc.
    @Test func aBatchLandsInOneEventUnderLogicalNames() throws {
        let env = try makeGame()
        let mods = env.mods, trash = ModTrash.root(gameDir: env.gameDir)
        for name in [".Alpha", ".[CP] Beta"] {
            try FileManager.default.createDirectory(atPath: path(mods, name, "i18n"),
                                                    withIntermediateDirectories: true)
        }
        let result = ModTrash.trash(
            modsPath: mods, trashRoot: trash, stamp: "20260924_194500",
            items: [.init(physical: ".Alpha", logicalLeaf: "Alpha"),
                    .init(physical: ".[CP] Beta", logicalLeaf: "[CP] Beta")])

        #expect(result.moved == [".Alpha", ".[CP] Beta"])
        #expect(result.failed.isEmpty)
        let event = "_Trash_20260924_194500"
        #expect(ModTrash.isUserEvent(trashRoot: trash, event: event))
        #expect(FileManager.default.fileExists(atPath: path(trash, event, "Alpha", "i18n")))
        #expect(FileManager.default.fileExists(atPath: path(trash, event, "[CP] Beta")))
        #expect(!FileManager.default.fileExists(atPath: path(mods, ".Alpha")))
    }

    @Test func aFailedEntryDoesNotStopTheBatch() throws {
        let env = try makeGame()
        let mods = env.mods, trash = ModTrash.root(gameDir: env.gameDir)
        try FileManager.default.createDirectory(atPath: path(mods, ".Alpha"),
                                                withIntermediateDirectories: true)
        let result = ModTrash.trash(
            modsPath: mods, trashRoot: trash, stamp: "20260924_194500",
            items: [.init(physical: ".Gone", logicalLeaf: "Gone"),
                    .init(physical: ".Alpha", logicalLeaf: "Alpha")])

        #expect(result.moved == [".Alpha"])
        #expect(result.failed.map(\.physical) == [".Gone"])
        #expect(FileManager.default.fileExists(atPath: path(trash, "_Trash_20260924_194500", "Alpha")))
    }

    @Test func aBatchThatMovesNothingLeavesNoEvent() throws {
        let env = try makeGame()
        let mods = env.mods, trash = ModTrash.root(gameDir: env.gameDir)
        let result = ModTrash.trash(
            modsPath: mods, trashRoot: trash, stamp: "20260924_194500",
            items: [.init(physical: ".Gone", logicalLeaf: "Gone")])

        #expect(result.moved.isEmpty)
        #expect(result.failed.count == 1)
        #expect(!FileManager.default.fileExists(atPath: path(trash, "_Trash_20260924_194500")))
    }

    @Test func aWholeEventIsRestoredPausedInOneGesture() throws {
        let env = try makeGame()
        let mods = env.mods, trash = ModTrash.root(gameDir: env.gameDir)
        let ev = try makeEvent(trash, "_Trash_20260924_194500")
        for name in ["Alpha", "Beta"] {
            try FileManager.default.createDirectory(atPath: path(ev, name, "i18n"),
                                                    withIntermediateDirectories: true)
        }
        let result = ModTrash.restoreEvent(modsPath: mods, trashRoot: trash, event: "_Trash_20260924_194500",
                                           stamp: "20260924_200000")

        #expect(result.moved == ["Alpha", "Beta"])
        #expect(result.failed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: path(mods, ".Alpha", "i18n")))
        #expect(FileManager.default.fileExists(atPath: path(mods, ".Beta")))
        #expect(!FileManager.default.fileExists(atPath: ev))
    }

    @Test func listingAnEventDoesNotDescendIntoMods() throws {
        let mods = makeTempModsDir()
        let ev = try makeEvent(mods, "_Trash_20260924_194500")
        try FileManager.default.createDirectory(atPath: path(ev, "Alpha", "assets", "deep"),
                                                withIntermediateDirectories: true)
        #expect(ModTrash.events(trashRoot: mods).first?.entries == ["Alpha"])
    }

    @Test func aBatchThatCannotOpenItsEventFailsWholeAndMovesNothing() throws {
        let env = try makeGame()
        let mods = env.mods, trash = ModTrash.root(gameDir: env.gameDir)
        try FileManager.default.createDirectory(atPath: path(mods, ".Alpha"),
                                                withIntermediateDirectories: true)
        // Dossier du jeu en lecture seule : ni la corbeille ni son marqueur
        // ne se posent.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: env.gameDir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: env.gameDir) }

        let result = ModTrash.trash(modsPath: mods, trashRoot: trash, stamp: "20260924_194500",
                                    items: [.init(physical: ".Alpha", logicalLeaf: "Alpha")])

        #expect(result.moved.isEmpty)
        #expect(result.failed.map(\.physical) == [".Alpha"])
        #expect(FileManager.default.fileExists(atPath: path(mods, ".Alpha")))
    }

    // MARK: - X115 — la corbeille hors de `Mods/`

    /// Le déposé ne laisse rien sous `Mods/` que SMAPI lirait comme un mod.
    @Test func aTrashedModLeavesNothingInMods() throws {
        let env = try makeGame()
        try FileManager.default.createDirectory(atPath: path(env.mods, "Alpha"),
                                                withIntermediateDirectories: true)
        _ = ModTrash.trash(modsPath: env.mods, trashRoot: ModTrash.root(gameDir: env.gameDir),
                           stamp: "20260925_120000",
                           items: [.init(physical: "Alpha", logicalLeaf: "Alpha")])
        #expect(try FileManager.default.contentsOfDirectory(atPath: env.mods).isEmpty)
        #expect(ModTrash.events(trashRoot: ModTrash.root(gameDir: env.gameDir)).count == 1)
    }

    /// Même seconde, même dossier de jeu : la quarantaine du vrai réparateur
    /// et un événement de corbeille ne se voient pas l'un l'autre — ni au
    /// compte, ni à la liste, ni au « Vider la quarantaine » (tout `_Trash_*`
    /// du dossier du jeu).
    @Test func quarantineAndTrashInTheSameSecondStayApart() throws {
        let env = try makeGame()
        let trash = ModTrash.root(gameDir: env.gameDir)
        try FileManager.default.createDirectory(atPath: path(env.mods, ".Alpha"),
                                                withIntermediateDirectories: true)
        try "x".write(toFile: path(env.mods, ".DS_Store"), atomically: true, encoding: .utf8)

        _ = ModTrash.trash(modsPath: env.mods, trashRoot: trash, stamp: ModTrash.makeStamp(),
                           items: [.init(physical: ".Alpha", logicalLeaf: "Alpha")])
        ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(ModTrash.quarantineItemCount(gameDir: env.gameDir) == 1)
        #expect(ModTrash.events(trashRoot: trash).map(\.entries) == [["Alpha"]])
        let quarantineSweep = try FileManager.default.contentsOfDirectory(atPath: env.gameDir)
            .filter { $0.hasPrefix("_Trash_") }
        #expect(!quarantineSweep.contains(ModTrash.rootFolderName))
        #expect(quarantineSweep.count == 1)
    }

    /// Un événement d'avant X115 (marqué, sous `Mods/`) sort vers la
    /// corbeille ; la quarantaine d'autrefois (sans marqueur) reste où elle
    /// est.
    @Test func legacyEventsLeaveModsButUnmarkedOnesStay() throws {
        let env = try makeGame()
        let trash = ModTrash.root(gameDir: env.gameDir)
        let legacy = try makeEvent(env.mods, "_Trash_20260910_101112")
        try "x".write(toFile: path(legacy, "Alpha"), atomically: true, encoding: .utf8)
        let unmarked = path(env.mods, "_Trash_20260909_090000")
        try FileManager.default.createDirectory(atPath: unmarked, withIntermediateDirectories: true)

        let result = ModTrash.migrateLegacyEvents(modsPath: env.mods, trashRoot: trash)

        #expect(result.moved == ["_Trash_20260910_101112"])
        #expect(result.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: legacy))
        #expect(FileManager.default.fileExists(atPath: unmarked))
        #expect(ModTrash.events(trashRoot: trash).map(\.entries) == [["Alpha"]])
        // Rejouée, la migration n'a plus rien à faire.
        #expect(ModTrash.migrateLegacyEvents(modsPath: env.mods, trashRoot: trash).moved.isEmpty)
    }

    /// Un nom déjà pris dans la corbeille se décale, jamais n'écrase.
    @Test func legacyMigrationNeverOverwrites() throws {
        let env = try makeGame()
        let trash = ModTrash.root(gameDir: env.gameDir)
        let existing = try makeEvent(trash, "_Trash_20260910_101112")
        try "x".write(toFile: path(existing, "Kept"), atomically: true, encoding: .utf8)
        let legacy = try makeEvent(env.mods, "_Trash_20260910_101112")
        try "x".write(toFile: path(legacy, "Moved"), atomically: true, encoding: .utf8)

        #expect(ModTrash.migrateLegacyEvents(modsPath: env.mods, trashRoot: trash).failed.isEmpty)

        let entries = ModTrash.events(trashRoot: trash).flatMap(\.entries).sorted()
        #expect(entries == ["Kept", "Moved"])
    }

    // MARK: - X114 — le compte vivant de la quarantaine

    /// La quarantaine est produite par le **vrai** réparateur, jamais posée à
    /// la main : les anciennes fixtures la mettaient sous `Mods/`, où il
    /// n'écrit jamais, et le badge valait zéro en production sans qu'un test
    /// rougisse.
    @Test func quarantaineDuReparateurCompte() throws {
        let env = try makeGame()
        try "x".write(toFile: path(env.mods, ".DS_Store"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            atPath: path(env.mods, "Dossier vide"), withIntermediateDirectories: true)

        let report = ModFolderRepairer().repairIfNeeded(gameDir: env.gameDir)

        #expect(report.quarantined.count == 2)
        #expect(ModTrash.quarantineItemCount(gameDir: env.gameDir) == 2)
    }

    /// Le cas voisin : une corbeille utilisateur sous `Mods/` n'est pas de la
    /// quarantaine.
    @Test func corbeilleUtilisateurPasComptee() throws {
        let env = try makeGame()
        try FileManager.default.createDirectory(
            atPath: path(env.mods, ".Alpha"), withIntermediateDirectories: true)
        try "x".write(toFile: path(env.mods, ".Alpha", "a.txt"), atomically: true, encoding: .utf8)

        let result = ModTrash.trash(modsPath: env.mods, trashRoot: ModTrash.root(gameDir: env.gameDir), stamp: "20260924_120000",
                                    items: [.init(physical: ".Alpha", logicalLeaf: "Alpha")])

        #expect(result.moved == [".Alpha"])
        #expect(ModTrash.quarantineItemCount(gameDir: env.gameDir) == 0)
    }

    @Test func quarantaineAbsenteVautZero() throws {
        let env = try makeGame()
        #expect(ModTrash.quarantineItemCount(gameDir: env.gameDir) == 0)
    }
}
