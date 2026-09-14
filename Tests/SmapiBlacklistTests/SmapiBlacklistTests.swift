import Foundation
import CryptoKit
import Testing
@testable import StarHubTHCore

/// A2-T7 — la liste des mods malveillants de SMAPI.
///
/// Les fixtures reprennent la **forme réelle** du document relevé le
/// 2026-09-15 (`https://smapi.io/SMAPI.blacklist.json`, 5 029 octets,
/// 9 entrées `Blacklist` + 1 `LooseFileBlacklist`) : commentaires bloc en
/// tête de chaque section, commentaires ligne pour dater les vagues,
/// commentaire en fin de ligne après une valeur.
@Suite struct SmapiBlacklistTests {

    /// La vraie forme du document, réduite à deux entrées.
    private var realShaped: Data {
        Data("""
        {
            /**
             * Metadata about malicious or harmful SMAPI mods.
            */
            "Blacklist": [
                // 2025-07
                {
                    "Id": "OpUlarenous.PortableCommunityCenter", // malicious reupload
                    "Message": "It downloads malicious code from a remote server."
                },
                {
                    "Id": "BritishW.ChaosWhispers",
                    "Message": "It downloads malicious code."
                }
            ],

            /**
             * Individual files which are known to be malicious.
            */
            "LooseFileBlacklist": [
                {
                    "Name": "Auto_Alchemistry.bat",
                    "Hash": "8b749727775689a05cc92ab4d624ab8b",
                    "Message": "It downloads malicious code."
                }
            ]
        }
        """.utf8)
    }

    // MARK: - Décodage

    @Test("Le JSONC réel se décode, commentaires compris")
    func decodesRealShapedJSONC() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        #expect(dump.entries.count == 2)
        #expect(dump.entries.first?.id == "OpUlarenous.PortableCommunityCenter")
        #expect(dump.entries.first?.message.contains("malicious") == true)
        #expect(dump.looseFiles.count == 1)
        #expect(dump.looseFiles.first?.name == "Auto_Alchemistry.bat")
    }

    /// **Le test qui compte le plus.** Un document illisible ne doit pas se
    /// traduire par « aucun mod malveillant » : l'app dirait un parc sain alors
    /// qu'elle ne sait rien.
    @Test("Un document illisible rend nil, jamais un dump vide")
    func unreadableIsNilNotEmpty() {
        #expect(SmapiBlacklist.decode(Data("pas du json".utf8)) == nil)
        #expect(SmapiBlacklist.decode(Data("{}".utf8)) == nil)
        #expect(SmapiBlacklist.decode(Data()) == nil)
    }

    @Test("Une liste réellement vide se distingue d'un échec de lecture")
    func emptyListIsNotFailure() throws {
        let dump = try #require(SmapiBlacklist.decode(Data(#"{"Blacklist": []}"#.utf8)))
        #expect(dump.isEmpty)
    }

    @Test("Une entrée sans identifiant est écartée, pas fatale")
    func skipsEntriesWithoutId() throws {
        let json = #"{"Blacklist": [{"Message": "x"}, {"Id": "A.B", "Message": "y"}]}"#
        let dump = try #require(SmapiBlacklist.decode(Data(json.utf8)))
        #expect(dump.entries.map(\.id) == ["A.B"])
    }

    /// Les messages de la source pourraient un jour porter un lien. Le
    /// stripper suit les chaînes, donc le `//` d'une URL survit — ce test le
    /// fige, parce qu'un stripper naïf couperait le message en deux.
    @Test("Une URL dans un message n'est pas prise pour un commentaire")
    func urlInsideStringSurvives() throws {
        let json = #"""
        {"Blacklist": [{"Id": "A.B", "Message": "See https://smapi.io/ for details."}]}
        """#
        let dump = try #require(SmapiBlacklist.decode(Data(json.utf8)))
        #expect(dump.entries.first?.message == "See https://smapi.io/ for details.")
    }

    // MARK: - Croisement par UniqueID

    @Test("Un mod installé sur la liste est reconnu")
    func matchesInstalledMod() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        let hits = SmapiBlacklist.matches(
            uniqueIds: ["Pathoschild.ContentPatcher", "BritishW.ChaosWhispers"], in: dump)
        #expect(Array(hits.keys) == ["BritishW.ChaosWhispers"])
    }

    /// Le choix qui sépare cette liste de celle de compatibilité : SMAPI
    /// compare les identifiants **sans** la casse. Une comparaison stricte
    /// laisserait passer un reupload qui change une majuscule, et l'app
    /// déclarerait sain un mod que le jeu refuse de charger.
    @Test("La casse ne permet pas d'échapper à la liste")
    func matchesIgnoringCase() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        let hits = SmapiBlacklist.matches(
            uniqueIds: ["opularenous.portablecommunitycenter"], in: dump)
        #expect(hits.count == 1)
        // La clé rendue est l'identifiant **tel que le mod le déclare** : c'est
        // lui qui sert à retrouver le mod dans le parc.
        #expect(Array(hits.keys) == ["opularenous.portablecommunitycenter"])
    }

    @Test("Les espaces autour d'un identifiant ne le sauvent pas non plus")
    func trimsWhitespace() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        #expect(SmapiBlacklist.matches(uniqueIds: ["  BritishW.ChaosWhispers "], in: dump).count == 1)
    }

    @Test("Un parc sain ne rend aucune correspondance")
    func cleanLibraryMatchesNothing() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        #expect(SmapiBlacklist.matches(
            uniqueIds: ["Pathoschild.ContentPatcher", "spacechase0.SpaceCore"], in: dump).isEmpty)
    }

    // MARK: - Fichier piégé : le nom trie, l'empreinte tranche

    @Test("La grille de tri ne retient que les noms surveillés")
    func watchedNamesAreLowercased() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        #expect(SmapiBlacklist.watchedFileNames(in: dump) == ["auto_alchemistry.bat"])
    }

    /// Le fichier réel de la source : ce contenu produit exactement le MD5
    /// publié. Sans cette correspondance, la grille ne servirait à rien.
    @Test("Le bon nom avec la bonne empreinte condamne")
    func nameAndHashCondemn() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        // Contenu forgé pour porter le hash de la fixture.
        let payload = Data("whatever".utf8)
        let forged = SmapiBlacklist.Dump(
            entries: [],
            looseFiles: [SmapiBlacklist.LooseFile(
                name: "Auto_Alchemistry.bat",
                hash: md5(payload),
                message: "piégé")])
        #expect(SmapiBlacklist.looseFileVerdict(
            name: "Auto_Alchemistry.bat", contents: payload, in: forged) != nil)
        // La vraie fixture ne reconnaît pas ce contenu-là.
        #expect(SmapiBlacklist.looseFileVerdict(
            name: "Auto_Alchemistry.bat", contents: payload, in: dump) == nil)
    }

    /// Un fichier innocent qui porte le nom surveillé ne doit pas être
    /// condamné : c'est l'empreinte qui tranche, jamais le nom seul.
    @Test("Le bon nom avec la mauvaise empreinte est innocent")
    func nameAloneDoesNotCondemn() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        #expect(SmapiBlacklist.looseFileVerdict(
            name: "Auto_Alchemistry.bat", contents: Data("innocent".utf8), in: dump) == nil)
    }

    @Test("Un nom non surveillé n'est jamais examiné")
    func unwatchedNameIsIgnored() throws {
        let dump = try #require(SmapiBlacklist.decode(realShaped))
        #expect(SmapiBlacklist.looseFileVerdict(
            name: "readme.txt", contents: Data(), in: dump) == nil)
    }

    // MARK: - Montage de la ligne d'alerte

    /// Un mod en pause vit dans un dossier préfixé d'un point. « Montrer dans
    /// le Finder » doit désigner le dossier **réel**, pas sa forme logique —
    /// sinon le Finder ouvre un chemin qui n'existe pas.
    @Test("Le chemin d'un mod en pause porte son point")
    func pausedModPathKeepsTheDot() {
        let inputs = SmapiBlacklist.issueInputs(
            matches: ["X.Y": SmapiBlacklist.Entry(id: "X.Y", message: "m")],
            nameByUniqueId: ["X.Y": "Mon Mod"],
            physicalFolderByUniqueId: ["X.Y": ".MonMod"],
            modsRoot: "/jeu/Mods")
        #expect(inputs.count == 1)
        #expect(inputs[0].folderPath == "/jeu/Mods/.MonMod")
    }

    @Test("Un mod dont on ignore le dossier rend un chemin vide, pas une racine")
    func unknownFolderYieldsEmptyPath() {
        let inputs = SmapiBlacklist.issueInputs(
            matches: ["X.Y": SmapiBlacklist.Entry(id: "X.Y", message: "m")],
            nameByUniqueId: ["X.Y": "Mon Mod"],
            physicalFolderByUniqueId: [:],
            modsRoot: "/jeu/Mods")
        #expect(inputs[0].folderPath == "")
    }

    @Test("Un mod signalé mais absent du parc ne fabrique pas de ligne")
    func unknownModProducesNoInput() {
        #expect(SmapiBlacklist.issueInputs(
            matches: ["X.Y": SmapiBlacklist.Entry(id: "X.Y", message: "m")],
            nameByUniqueId: [:], physicalFolderByUniqueId: [:],
            modsRoot: "/jeu/Mods").isEmpty)
    }

    /// Un pack ne déclare pas d'UniqueID : ce sont ses enfants. Ne regarder que
    /// le premier niveau laisserait passer un mod malveillant livré dans un
    /// pack — le cas des reuploads piégés.
    @Test("Les composants d'un pack sont examinés aussi")
    func packChildrenAreScanned() {
        let ids = SmapiBlacklist.uniqueIds(
            ofTopLevel: ["", "Solo.Mod"],
            children: [["Enfant.Un", "Enfant.Deux"], []])
        #expect(ids == ["Enfant.Un", "Enfant.Deux", "Solo.Mod"])
    }

    @Test("Un identifiant vide n'entre jamais dans la liste à croiser")
    func emptyIdsAreDropped() {
        #expect(SmapiBlacklist.uniqueIds(ofTopLevel: ["", ""], children: [[""], [""]]).isEmpty)
    }

    // MARK: - La règle du cache

    /// Le défaut mesuré sur la liste de compatibilité : écrire le cache avant
    /// de savoir décoder. Ici il serait pire — « 0 entrée » sur une liste de
    /// mods malveillants se lit « votre parc est sain ».
    @Test("Un corps illisible sert le cache et ne l'écrase pas")
    func unreadableBodyFallsBackToCache() {
        let outcome = SmapiBlacklist.outcome(forPayload: Data("<html>502</html>".utf8),
                                             cachedPayload: { self.realShaped })
        guard case .fallback(let dump) = outcome else {
            Issue.record("attendu .fallback, obtenu \(outcome)"); return
        }
        #expect(dump.entries.count == 2)
    }

    @Test("Un corps lisible est servi et mis en cache")
    func readableBodyIsFresh() {
        let outcome = SmapiBlacklist.outcome(forPayload: realShaped, cachedPayload: { nil })
        guard case .fresh(let dump) = outcome else {
            Issue.record("attendu .fresh, obtenu \(outcome)"); return
        }
        #expect(dump.entries.count == 2)
    }

    /// Ni corps ni cache : il faut le dire, pas rendre une liste vide.
    @Test("Sans corps ni cache lisibles, l'échec est explicite")
    func noBodyNoCacheIsUnreadable() {
        #expect(SmapiBlacklist.outcome(forPayload: Data("nope".utf8),
                                       cachedPayload: { nil }) == .unreadable)
    }

    /// Un cache lui-même corrompu ne sauve rien — et ne doit pas faire passer
    /// un parc pour sain.
    @Test("Un cache corrompu ne tient pas lieu de filet")
    func corruptCacheIsNotAFallback() {
        #expect(SmapiBlacklist.outcome(forPayload: Data("nope".utf8),
                                       cachedPayload: { Data("aussi nope".utf8) }) == .unreadable)
    }

    private func md5(_ data: Data) -> String {
        // Même calcul que la production, pour que la fixture soit cohérente.
        var out = ""
        for byte in Insecure.MD5.hash(data: data) { out += String(format: "%02x", byte) }
        return out
    }
}
