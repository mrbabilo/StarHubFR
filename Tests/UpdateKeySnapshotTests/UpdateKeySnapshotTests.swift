import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct UpdateKeySnapshotTests {

    private var tmp: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("uks-\(UUID().uuidString)")
    }

    private func write(_ content: String, base: URL, relativePath: String,
                       as data: Data? = nil) throws {
        let url = base.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data { try data.write(to: url) }
        else { try content.write(toFile: url.path, atomically: true, encoding: .utf8) }
    }

    @Test func simpleModWithConfigAndI18n() throws {
        let dir = tmp
        try write(#"{"Enable":true,"Count":3}"#, base: dir, relativePath: "config.json")
        try write(#"{"a":"A","b":"B"}"#, base: dir, relativePath: "i18n/default.json")
        try write(#"{"a":"fr"}"#, base: dir, relativePath: "i18n/fr.json")

        let snap = UpdateKeySnapshot.read(folder: dir)

        #expect(snap.configKeys == ["Enable", "Count"])
        #expect(snap.config?["Enable"] == "true", "la valeur est portée pour le delta et le report")
        #expect(Set((snap.english[""] ?? [:]).keys) == ["a", "b"])
        #expect(snap.english[""]?["a"] == "A")
        #expect(Set((snap.french[""] ?? [:]).keys) == ["a"])
    }

    @Test func enJsonFallsBackWhenDefaultIsMissing() throws {
        let dir = tmp
        try write(#"{"x":"X"}"#, base: dir, relativePath: "i18n/en.json")
        let snap = UpdateKeySnapshot.read(folder: dir)
        #expect(Set((snap.english[""] ?? [:]).keys) == ["x"])
    }

    @Test func packComponentsAreSeparated() throws {
        let dir = tmp
        try write(#"{"root":"R"}"#, base: dir, relativePath: "i18n/default.json")
        try write(#"{"manifest":true}"#, base: dir, relativePath: "Kid/manifest.json")
        try write(#"{"kid":"K"}"#, base: dir, relativePath: "Kid/i18n/default.json")
        try write(#"{"kid":"fr"}"#, base: dir, relativePath: "Kid/i18n/fr.json")

        let snap = UpdateKeySnapshot.read(folder: dir)
        #expect(Set((snap.english[""] ?? [:]).keys) == ["root"])
        #expect(Set((snap.english["Kid"] ?? [:]).keys) == ["kid"])
        #expect(Set((snap.french["Kid"] ?? [:]).keys) == ["kid"])
    }

    @Test func absentConfigIsNilNotEmpty() throws {
        let dir = tmp
        try write(#"{"a":"A"}"#, base: dir, relativePath: "i18n/default.json")
        let snap = UpdateKeySnapshot.read(folder: dir)
        #expect(snap.config == nil)
        #expect(Set((snap.english[""] ?? [:]).keys) == ["a"])
    }

    @Test func utf16FrenchFileIsRead() throws {
        let dir = tmp
        try write(#"{"a":"A"}"#, base: dir, relativePath: "i18n/default.json")
        let utf16 = #"{"a":"en français"}"#.data(using: .utf16)!
        try write("", base: dir, relativePath: "i18n/fr.json", as: utf16)

        let snap = UpdateKeySnapshot.read(folder: dir)
        #expect(Set((snap.french[""] ?? [:]).keys) == ["a"])
    }

    @Test func bomConfigIsRead() throws {
        let dir = tmp
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(#"{"Enable":true}"#.utf8))
        try write("", base: dir, relativePath: "config.json", as: data)

        let snap = UpdateKeySnapshot.read(folder: dir)
        #expect(snap.configKeys == ["Enable"])
    }

    @Test func crlfConfigIsRead() throws {
        // Fixture CRLF : le JSON parse par JSONSerialization, mais le texte
        // doit décoder avec ses \r\n sans perdre la dernière clé (piège
        // documenté : CRLF compte pour un seul Character).
        let dir = tmp
        try write("{\r\n  \"a\": \"1\",\r\n  \"b\": \"2\"\r\n}",
                  base: dir, relativePath: "config.json")
        let snap = UpdateKeySnapshot.read(folder: dir)
        #expect(snap.configKeys == ["a", "b"])
    }

    @Test func lenientI18nFilesAreRead() throws {
        // Le JSON strict refusait 125 des 241 fichiers i18n EN/FR du parc
        // (commentaires, virgules finales) que le jeu charge très bien : le
        // composant disparaissait du snapshot et le delta comptait faux dans
        // les deux sens. Même tolérance que l'onglet diff.
        let dir = tmp
        try write("""
            // Section greeting
            {
              "a": "A", /* bloc */
              "b": "B",
            }
            """, base: dir, relativePath: "i18n/default.json")
        try write(#"{"a":"fr","b":"fr"}"#, base: dir, relativePath: "i18n/fr.json")

        let snap = UpdateKeySnapshot.read(folder: dir)
        #expect(Set((snap.english[""] ?? [:]).keys) == ["a", "b"])
        #expect(Set((snap.french[""] ?? [:]).keys) == ["a", "b"])
    }

    @Test func numericI18nValueIsKept() throws {
        // lenientObject plutôt que parse : une valeur numérique est chargée
        // par le jeu (Newtonsoft mesuré) — refuser le fichier entier perdrait
        // le composant au snapshot pour un i18n pourtant lisible.
        let dir = tmp
        try write(#"{"a":"A","count":3}"#, base: dir, relativePath: "i18n/default.json")

        let snap = UpdateKeySnapshot.read(folder: dir)
        #expect(snap.english[""]?["count"] == "3")
        #expect(snap.english[""]?["a"] == "A")
    }

    @Test func missingFolderYieldsEmptySnapshot() throws {
        let snap = UpdateKeySnapshot.read(folder: tmp)
        #expect(snap.config == nil)
        #expect(snap.english.isEmpty && snap.french.isEmpty)
    }
}
