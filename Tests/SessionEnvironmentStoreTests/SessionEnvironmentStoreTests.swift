import Testing
import Foundation
@testable import StarHubTHCore

/// D2-T3 §4/§6 — le store sur fichiers temporaires : vrai journal, vrai
/// arbre Mods/. La date du journal est comparée à la seconde près (piège
/// setAttributes : deux Date après aller-retour disque ne sont pas ==).
@MainActor
struct SessionEnvironmentStoreTests {

    private func makeTemp(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString)").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        return url
    }

    private func makeModsTree(root: URL) throws -> (mods: [ModItem], modsRoot: String) {
        // Racine « SVE » avec deux packs ; racine simple « Lone » ; racine
        // en pause « .PausedMod » avec un pack sur le disque — le scan doit
        // l'ignorer (spec §3.1), le dossier reste là pour le prouver.
        let fm = FileManager.default
        for (dir, content) in [
            ("SVE/[CP]", ["content.json": #"{"Format":"2.5.0","Changes":[{"Action":"Load"},{"Action":"Load"}]}"#]),
            ("SVE/[FTM]", ["content.json": #"{"Format":"2.5.0","Changes":[{"Action":"Load"}]}"#]),
            ("Lone", ["content.json": #"{"Format":"2.5.0","Changes":[{"Action":"Load"},{"Action":"Load"},{"Action":"Load"}]}"#]),
            (".PausedMod/Pack", ["content.json": #"{"Format":"2.5.0","Changes":[{"Action":"Load"}]}"#]),
        ] {
            let d = root.appendingPathComponent(dir)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            for (file, text) in content {
                try text.write(to: d.appendingPathComponent(file), atomically: true, encoding: .utf8)
            }
        }
        // Vérifié : `components` = `isGroup ? (children ?? []) : [self]`
        // (ModItem.swift:62), folderName du composant = chemin relatif
        // « Racine/Composant ». ModItem: Sendable (ModItem.swift:110), init
        // complet ModItem.swift:111 — seuls les champs utiles sont remplis.
        // La racine en pause n'a pas de composant dans la liste des mods
        // actifs : scanGroups doit retrouver son pack via le
        // physicalFolderName de la racine (test dédié ci-dessous).
        func mod(_ folder: String, name: String, enabled: Bool = true,
                 children: [ModItem]? = nil) -> ModItem {
            ModItem(uniqueId: "", name: name, folderName: folder, version: "",
                    author: "", description: "", nexusUrl: "", nexusModId: "",
                    isEnabled: enabled, dependencies: [],
                    children: children, isGroup: children != nil)
        }
        let sve = mod("SVE", name: "Stardew Valley Expanded",
                      children: [mod("SVE/[CP]", name: "[CP] SVE"),
                                 mod("SVE/[FTM]", name: "[FTM] SVE")])
        let paused = mod("PausedMod", name: "Paused SVE", enabled: false)
        return ([sve, paused, mod("Lone", name: "Lone CP")], root.path)
    }

    @Test func reportCombinesJournalAndDisk() async throws {
        let dir = try makeTemp("log.txt")
        let log = """
        [game] Stardew Valley 1.6
        [18:56:10 TRACE Modern Config Menu] Registered config menu for Modern Config Menu (palmhacker13.ModernConfigMenu).
        [18:56:27 TRACE 互动气泡 Interaction Bubbles] Registered with Generic Mod Config Menu.
        """
        try log.write(to: dir, atomically: true, encoding: .utf8)
        let (mods, modsRoot) = try makeModsTree(root: dir.deletingLastPathComponent()
            .appendingPathComponent("Mods"))
        try FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)

        let store = SessionEnvironmentStore(logURL: dir)
        await store.reload(mods: mods, gameDir: (modsRoot as NSString).deletingLastPathComponent)

        #expect(store.status == .ready)
        let report = try #require(store.report)
        #expect(report.slo == nil)                       // pas de ligne [OPTIMIZER CONFIG]
        #expect(report.menus.count == 2)
        #expect(report.menus.contains { $0.modId == "palmhacker13.ModernConfigMenu" })
        #expect(report.groups.count == 2)                 // SVE (2 packs), Lone — pause exclue (spec §3.1)
        #expect(report.totalPatches == 6)                 // 2+1 (SVE) + 3 (Lone)
        #expect(report.journalDate != nil)
    }

    @Test func missingLogGivesNilReportNotEternalLoading() async throws {
        let store = SessionEnvironmentStore(logURL: try makeTemp("absent.txt"))
        await store.reload(mods: [], gameDir: nil)
        #expect(store.status == .ready)
        #expect(store.report == nil)
    }

    @Test func sloLineReachesTheReport() async throws {
        let dir = try makeTemp("log.txt")
        let log = "[12:00:00 INFO Stardew Loading Optimizer] [OPTIMIZER CONFIG] profile=1, fastWarp=configured=True,effective=True,reason=single-player-session."
        try log.write(to: dir, atomically: true, encoding: .utf8)
        let store = SessionEnvironmentStore(logURL: dir)
        await store.reload(mods: [], gameDir: nil)
        let report = try #require(store.report)
        #expect(report.slo?.profile == 1)
    }

    @Test func pausedRootExcluded() async throws {
        // Spec §3.1 : les packs des dossiers préfixés point (mods en pause)
        // ne comptent pas — la racine désactivée n'entre pas dans les groupes,
        // et rien n'est lu sous « .PausedMod ».
        let (mods, modsRoot) = try makeModsTree(root: makeTemp("Mods"))
        var groups = SessionEnvironmentStore.scanGroups(mods: mods, modsRoot: modsRoot)
        #expect(!groups.contains { $0.rootName == "Paused SVE" })
        groups.removeAll { $0.rootName == "Paused SVE" }
        #expect(groups.map(\.rootName) == ["Stardew Valley Expanded", "Lone CP"])
        let sve = groups[0]
        #expect(sve.packs.map(\.packName) == ["[CP] SVE", "[FTM] SVE"])
        #expect(sve.totalPatches == 3)
        #expect(groups[1].totalPatches == 3)
    }
}

extension SessionEnvironmentStoreTests {
    @Test func stardropiumMeasurementsFollowJournalReplacement() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("SMAPI-latest.txt")
        try "[14:54:12 INFO Stardropium] [Morning Memory Optimizer (Background)] RAM: 1561 MB -> 1565 MB (Managed Heap: 3749 MB -> 3751 MB, 0 cached textures purged/bounded).".write(to: log, atomically: true, encoding: .utf8)
        let store = SessionEnvironmentStore(logURL: log)
        await store.reload(mods: [], gameDir: nil)
        #expect(store.report?.stardropiumMemory.samples.count == 1)
        #expect(store.report?.stardropiumMemory.samples.first?.residentDelta == 4)
        try FileManager.default.removeItem(at: log)
        await store.reload(mods: [], gameDir: nil)
        #expect(store.report == nil)
        try "[12:00:00 INFO SMAPI] New session without Stardropium".write(to: log, atomically: true, encoding: .utf8)
        await store.reload(mods: [], gameDir: nil)
        #expect(store.report?.stardropiumMemory.samples.isEmpty == true)
    }
}
