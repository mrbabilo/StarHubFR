import Testing
import Foundation
@testable import StarHubTHCore

/// Le magasin d'archives Nexus (X103-C). Chaque test reçoit un dossier
/// temporaire : rien n'écrit jamais dans le vrai Application Support — 582
/// exécutions y avaient pollué de vrais backups avant que les managers ne
/// soient injectés.
@Suite("Magasin d'archives Nexus")
struct NexusArchiveStoreTests {

    /// Un magasin neuf dans un dossier à lui, plus l'archive bidon qu'on y dépose.
    private func makeStore() throws -> (NexusArchiveStore, URL, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nexus-archives-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let src = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let archive = src.appendingPathComponent("SomeMod-1.2.3.zip")
        try Data(repeating: 0x50, count: 2048).write(to: archive)
        return (NexusArchiveStore(root: root.appendingPathComponent("store")), root, archive)
    }

    @Test("une archive gardée se relit par son UniqueID et sa version")
    func keepThenLookUp() throws {
        let (store, _, archive) = try makeStore()
        let entry = try store.keep(archive: archive, uniqueId: "Pathos.SomeMod",
                                   version: "1.2.3", modName: "Some Mod")
        #expect(entry.uniqueId == "Pathos.SomeMod")
        #expect(entry.version == "1.2.3")
        #expect(entry.byteSize == 2048)
        #expect(store.entries().count == 1)
        #expect(store.entry(uniqueId: "Pathos.SomeMod", version: "1.2.3") != nil)
        // La version compte : une autre version n'est pas la même archive.
        #expect(store.entry(uniqueId: "Pathos.SomeMod", version: "1.2.4") == nil)
    }

    @Test("l'archive d'origine n'est pas déplacée, elle est copiée")
    func keepCopiesRatherThanMoves() throws {
        let (store, _, archive) = try makeStore()
        _ = try store.keep(archive: archive, uniqueId: "A.B", version: "1", modName: "B")
        // Le flux d'installation efface l'archive lui-même, par son propre
        // `discardDownloaded` : la déplacer sous ses pieds casserait ce ménage.
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("deux mods qui partagent un identifiant Nexus restent deux archives")
    func distinctUniqueIdsDoNotCollide() throws {
        let (store, _, archive) = try makeStore()
        _ = try store.keep(archive: archive, uniqueId: "Author.First", version: "1", modName: "First")
        _ = try store.keep(archive: archive, uniqueId: "Author.Second", version: "1", modName: "Second")
        // 58 identifiants Nexus sont partagés sur le parc, l'id 8828 en couvre
        // trois : c'est l'UniqueID qui sépare, jamais l'id Nexus.
        #expect(store.entries().count == 2)
    }

    @Test("garder deux fois la même version ne fait pas deux entrées")
    func keepingTwiceReplaces() throws {
        let (store, _, archive) = try makeStore()
        _ = try store.keep(archive: archive, uniqueId: "A.B", version: "2.0", modName: "B")
        _ = try store.keep(archive: archive, uniqueId: "A.B", version: "2.0", modName: "B")
        #expect(store.entries().count == 1)
    }

    @Test("le poids total est la somme des archives")
    func totalBytes() throws {
        let (store, _, archive) = try makeStore()
        _ = try store.keep(archive: archive, uniqueId: "A.B", version: "1", modName: "B")
        _ = try store.keep(archive: archive, uniqueId: "A.C", version: "1", modName: "C")
        #expect(store.totalBytes() == 4096)
    }

    @Test("supprimer une archive la retire du disque et de l'index")
    func removeDeletesBoth() throws {
        let (store, _, archive) = try makeStore()
        let entry = try store.keep(archive: archive, uniqueId: "A.B", version: "1", modName: "B")
        let stored = store.fileURL(of: entry)
        #expect(FileManager.default.fileExists(atPath: stored.path))
        store.remove(entry)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
        #expect(store.entries().isEmpty)
    }

    @Test("vider le magasin n'en laisse rien")
    func removeAll() throws {
        let (store, _, archive) = try makeStore()
        _ = try store.keep(archive: archive, uniqueId: "A.B", version: "1", modName: "B")
        _ = try store.keep(archive: archive, uniqueId: "A.C", version: "1", modName: "C")
        store.removeAll()
        #expect(store.entries().isEmpty)
        #expect(store.totalBytes() == 0)
    }

    @Test("l'index survit à un nouveau magasin sur le même dossier")
    func indexPersists() throws {
        let (store, root, archive) = try makeStore()
        _ = try store.keep(archive: archive, uniqueId: "A.B", version: "1", modName: "B")
        let reopened = NexusArchiveStore(root: root.appendingPathComponent("store"))
        #expect(reopened.entries().count == 1)
        #expect(reopened.entry(uniqueId: "A.B", version: "1") != nil)
    }

    @Test("une entrée dont le fichier a disparu ne se rend pas")
    func missingFileIsNotServed() throws {
        let (store, _, archive) = try makeStore()
        let entry = try store.keep(archive: archive, uniqueId: "A.B", version: "1", modName: "B")
        try FileManager.default.removeItem(at: store.fileURL(of: entry))
        // Le disque est la vérité : l'index peut mentir (ménage manuel du
        // Finder, disque plein). Servir un chemin mort ferait échouer la
        // réinstallation avec une erreur incompréhensible.
        #expect(store.entry(uniqueId: "A.B", version: "1") == nil)
    }

    // MARK: - Rétention

    @Test("la rétention garde tout ce qui a moins de 30 jours")
    func retentionKeepsRecent() throws {
        let (store, _, archive) = try makeStore()
        for i in 0..<8 {
            var e = try store.keep(archive: archive, uniqueId: "A.M\(i)", version: "1", modName: "M\(i)")
            e.timestamp = Date().addingTimeInterval(-Double(i) * 24 * 3600)
            store.replaceForTesting(e)
        }
        #expect(store.applyRetention() == 0)
        #expect(store.entries().count == 8)
    }

    @Test("au-delà de 30 jours, une seule archive par mois survit")
    func retentionKeepsOnePerMonthBeyondThirtyDays() throws {
        let (store, _, archive) = try makeStore()
        // Cinq archives dans le même mois, toutes vieilles de plus de 200 jours,
        // plus six récentes pour dépasser le plancher des cinq gardées d'office.
        for i in 0..<6 {
            var e = try store.keep(archive: archive, uniqueId: "A.Recent\(i)", version: "1", modName: "R\(i)")
            e.timestamp = Date().addingTimeInterval(-Double(i) * 3600)
            store.replaceForTesting(e)
        }
        for i in 0..<5 {
            var e = try store.keep(archive: archive, uniqueId: "A.Old\(i)", version: "1", modName: "O\(i)")
            e.timestamp = Date().addingTimeInterval(-(200 * 24 * 3600) - Double(i) * 3600)
            store.replaceForTesting(e)
        }
        #expect(store.entries().count == 11)
        let deleted = store.applyRetention()
        #expect(deleted == 4)             // 5 vieilles du même mois → 1 gardée
        #expect(store.entries().count == 7)
    }

    @Test("la rétention ne descend jamais sous cinq archives")
    func retentionNeverGoesBelowFloor() throws {
        let (store, _, archive) = try makeStore()
        for i in 0..<4 {
            var e = try store.keep(archive: archive, uniqueId: "A.Old\(i)", version: "1", modName: "O\(i)")
            e.timestamp = Date().addingTimeInterval(-(400 * 24 * 3600) - Double(i) * 86400 * 40)
            store.replaceForTesting(e)
        }
        // Quatre archives, toutes très vieilles et chacune dans son mois : rien
        // ne part, le plancher protège avant même que la règle des mois joue.
        #expect(store.applyRetention() == 0)
        #expect(store.entries().count == 4)
    }

    /// X123 — un index illisible était relu vide : la prochaine archive gardée
    /// le réécrivait avec elle seule, et les autres pesaient dans `files/` sans
    /// être montrées ni nettoyées. L'index se reconstruit désormais depuis les
    /// fichiers (leur nom porte `UniqueID@version`), et l'index abîmé est mis
    /// de côté avant d'être remplacé.
    @Test("un index illisible se reconstruit depuis les archives présentes")
    func unreadableIndexIsRebuiltFromFiles() throws {
        let (store, root, archive) = try makeStore()
        try store.keep(archive: archive, uniqueId: "A.Mod", version: "1.0", modName: "A")
        try store.keep(archive: archive, uniqueId: "B.Mod", version: "2.0", modName: "B")
        let storeRoot = root.appendingPathComponent("store")
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: storeRoot.appendingPathComponent("index.json"))

        #expect(Set(store.entries().map(\.id)) == ["A.Mod@1.0", "B.Mod@2.0"])

        try store.keep(archive: archive, uniqueId: "C.Mod", version: "3.0", modName: "C")
        #expect(Set(store.entries().map(\.id)) == ["A.Mod@1.0", "B.Mod@2.0", "C.Mod@3.0"])
        #expect(store.totalBytes() == 3 * 2048)
        let aside = try FileManager.default.contentsOfDirectory(atPath: storeRoot.path)
            .filter { $0.hasPrefix("index.unreadable-") }
        #expect(aside.count == 1)
        if let name = aside.first {
            #expect(FileManager.default.contents(atPath: storeRoot.appendingPathComponent(name).path) == garbage)
        }
    }

    @Test("un index disparu sous des archives présentes se reconstruit aussi")
    func missingIndexIsRebuiltFromFiles() throws {
        let (store, root, archive) = try makeStore()
        try store.keep(archive: archive, uniqueId: "A.Mod", version: "1.0", modName: "A")
        try FileManager.default.removeItem(at: root.appendingPathComponent("store/index.json"))
        #expect(store.entries().map(\.id) == ["A.Mod@1.0"])
        #expect(store.entry(uniqueId: "A.Mod", version: "1.0") != nil)
    }
}
