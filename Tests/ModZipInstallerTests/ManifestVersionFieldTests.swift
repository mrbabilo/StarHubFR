import Foundation
import Testing
@testable import StarHubTHCore

/// `ManifestVersionReader` a été écrit pour qu'il n'y ait **qu'une** lecture du
/// champ `Version` d'un manifest — son propre en-tête le dit. Il en restait
/// trois : le scan de la bibliothèque l'utilise sur son chemin « cache chaud »
/// mais pas sur son chemin « cache froid » (deux lectures du même champ à
/// quarante lignes d'écart, donc une version qui peut changer selon l'état du
/// cache), et `ModManifest.init(dict:)` gardait la sienne.
///
/// Les trois divergent sur trois formes que SMAPI accepte : une partie de
/// version écrite en chaîne (`"MajorVersion": "2"`), une chaîne entourée
/// d'espaces, et une chaîne entièrement blanche. Aucun des 1 095 manifests du
/// parc de référence ne les porte aujourd'hui (mesuré le 2026-09-04) — ces
/// tests verrouillent la lecture commune avant qu'un mod ne les apporte.
struct ManifestVersionFieldTests {
    private func manifest(version: String) -> ModManifest? {
        let json = """
        { "Name": "T", "UniqueID": "test.mod", "Version": \(version) }
        """
        let raw = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        return ModManifest(dict: raw)
    }

    @Test func versionPartsWrittenAsStringsAreRead() {
        // `{"MajorVersion": "2"}` : le `as? Int` de la lecture locale échouait
        // et retombait sur la valeur par défaut — 2.1.0 s'affichait 1.0.0.
        let m = manifest(version: "{ \"MajorVersion\": \"2\", \"MinorVersion\": \"1\", \"PatchVersion\": \"3\" }")
        #expect(m?.version == "2.1.3")
    }

    @Test func versionObjectWithIntegerPartsStaysUnchanged() {
        // La forme la plus courante de l'objet — le seul mod du parc qui
        // l'emploie (*LovedLabels*, 2.1.0). Elle ne doit pas bouger.
        let m = manifest(version: "{ \"MajorVersion\": 2, \"MinorVersion\": 1, \"PatchVersion\": 0 }")
        #expect(m?.version == "2.1.0")
    }

    @Test func paddedVersionStringIsTrimmed() {
        // Une version entourée d'espaces s'affichait telle quelle, et ne
        // s'appariait pas avec la même version lue ailleurs.
        let m = manifest(version: "\"  1.2.3  \"")
        #expect(m?.version == "1.2.3")
    }

    @Test func blankVersionStringIsUnknown() {
        // Une version entièrement blanche vaut une version absente : elle
        // laissait une ligne « v » sans rien derrière.
        let m = manifest(version: "\"   \"")
        #expect(m?.version == "Unknown")
    }

    @Test func missingVersionIsUnknown() {
        let json = "{ \"Name\": \"T\", \"UniqueID\": \"test.mod\" }"
        let raw = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        #expect(ModManifest(dict: raw)?.version == "Unknown")
    }

    @Test func plainVersionStringIsUnchanged() {
        #expect(manifest(version: "\"1.4.2\"")?.version == "1.4.2")
    }
}
