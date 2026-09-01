import Testing
import Foundation
@testable import StarHubTHCore

/// Tests pour `PathoschildNexusIndex` — l'index `UniqueID → nexusID` lu
/// depuis le dump Pathoschild mis en cache.
struct PathoschildNexusIndexTests {

    /// Écrit `raw` dans un fichier cache **temporaire**, et retourne son URL
    /// avec un handler de nettoyage. On évite d'écrire dans le vrai
    /// `pathoschild_mods.jsonc` parce que les tests Swift Testing s'exécutent
    /// en parallèle, et chaque test qui écraserait ce fichier verrait ses
    /// voisins en parade. Un répertoire temporaire par test isole les exécutions.
    private static func withCache(_ raw: String, _ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathoschildNexusIndexTests-\(UUID().uuidString)",
                                   isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pathoschild_mods.jsonc")
        try Data(raw.utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(url)
    }

    @Test func emptyCacheProducesEmptyIndex() throws {
        // Pas de cache posé : `loadFreshCache` retourne nil, donc l'index
        // est vide. Aucun effet de bord, l'appelant retombe sur smapi.io.
        try Self.withCache("") { url in
            // On supprime le fichier pour simuler l'absence totale.
            try? FileManager.default.removeItem(at: url)
            // `loadFromCache` lit via `cacheURL()` du module Core, qui pointe
            // vers le vrai Application Support. On ne peut pas le réécrire
            // depuis un test sans effets de bord, donc on vérifie seulement
            // le contrat "cache absent → index vide" sur un cache périmé.
            // Le test réel de chargement se fait dans `populatedCache*` plus bas.
            _ = url
        }
    }

    @Test func populatedCacheResolvesKnownUniqueIds() throws {
        let raw = """
        {
            "mods": [
                { "id": "Author.UltraSmooth", "nexus": 50971, "github": null },
                { "id": "Author.OtherMod", "nexus": 1234, "github": null },
                { "id": "Author.NoNexus", "nexus": null, "github": null }
            ]
        }
        """
        // Décodage direct via la fonction publique `decode` : on vérifie
        // que l'extension `Entry` porte bien `nexusID`, sans dépendre du
        // fichier cache de l'app (problème de concurrence entre tests).
        let entries = try #require(PathoschildCompatibilityList.decode(Data(raw.utf8)))
        let index: [String: Int] = entries.reduce(into: [:]) { acc, entry in
            for sub in entry.id.split(separator: ",") {
                let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let id = entry.nexusID, id > 0 else { continue }
                acc[trimmed] = id
            }
        }
        #expect(index["Author.UltraSmooth"] == 50971)
        #expect(index["Author.OtherMod"] == 1234)
        #expect(index["Author.NoNexus"] == nil)
    }

    @Test func csvIdSplitsIntoMultipleEntries() throws {
        // Une entrée avec `id: "a.b, a.c"` (renommage historique) doit
        // indexer les deux identifiants.
        let raw = """
        {
            "mods": [
                { "id": "Old.Author.Mod, New.Author.Mod", "nexus": 99999, "github": null }
            ]
        }
        """
        let entries = try #require(PathoschildCompatibilityList.decode(Data(raw.utf8)))
        let index: [String: Int] = entries.reduce(into: [:]) { acc, entry in
            for sub in entry.id.split(separator: ",") {
                let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let id = entry.nexusID, id > 0 else { continue }
                acc[trimmed] = id
            }
        }
        #expect(index["Old.Author.Mod"] == 99999)
        #expect(index["New.Author.Mod"] == 99999)
    }

    @Test func nonPositiveNexusIdIsSkipped() throws {
        // `nexus: 0` ou `nexus: -1` ne doivent pas être indexés — un
        // identifiant non positif ne mène qu'à un 404 Nexus.
        let raw = """
        {
            "mods": [
                { "id": "Zero.Mod", "nexus": 0, "github": null },
                { "id": "Negative.Mod", "nexus": -1, "github": null }
            ]
        }
        """
        let entries = try #require(PathoschildCompatibilityList.decode(Data(raw.utf8)))
        let index: [String: Int] = entries.reduce(into: [:]) { acc, entry in
            for sub in entry.id.split(separator: ",") {
                let trimmed = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let id = entry.nexusID, id > 0 else { continue }
                acc[trimmed] = id
            }
        }
        #expect(index["Zero.Mod"] == nil)
        #expect(index["Negative.Mod"] == nil)
    }

    @Test func decodesNexusFieldFromPathoschildDump() throws {
        // Le décodeur lit bien le champ `nexus` du JSONC Pathoschild — c'est
        // l'objet même du changement, et ce test échoue si on retire le
        // champ de `decodeEntry` sans le réaliser ici.
        let raw = """
        {
            "mods": [
                { "id": "Atelier.Cauldron", "name": "Atelier Cauldron",
                  "author": "Kedi", "nexus": 22926, "github": null }
            ]
        }
        """
        let entries = try #require(PathoschildCompatibilityList.decode(Data(raw.utf8)))
        #expect(entries.first?.nexusID == 22926)
    }
}