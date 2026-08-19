import Foundation
import Testing
@testable import StarHubTHCore

/// Tâche 9 du plan P2b — résolution des sources du glossaire (XNB d'abord,
/// layout bundle macOS, unpacked en repli) et cache Application Support
/// atomique (spec §4-§5). Tout se joue sur des dossiers temporaires.
struct GlossaryStoreTests {

    private var root: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GlossaryStoreTests-\(UUID().uuidString)")
    }

    private func mkdirs(_ urls: [URL]) throws {
        for url in urls {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Fixture XNB minimale

    /// Copie raccourcie de `Tests/XnbStringDictionaryReaderTests` (SPM ne
    /// partage pas les fichiers entre cibles de test) : dictionnaire
    /// string→string non compressé, layout mesuré en tâche 5.
    private enum Fx {
        static func u32(_ value: Int) -> [UInt8] {
            [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
             UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
        }

        static func vint(_ value: Int) -> [UInt8] {
            var v = value
            var out: [UInt8] = []
            repeat {
                var byte = UInt8(v & 0x7F)
                v >>= 7
                if v != 0 { byte |= 0x80 }
                out.append(byte)
            } while v != 0
            return out
        }

        static func string(_ s: String) -> [UInt8] {
            u32(s.utf8.count) + Array(s.utf8)
        }

        static func xnb(entries: [(String, String)]) -> Data {
            var content: [UInt8] = vint(2)   // deux readers : Dictionary, String
            content += string("Microsoft.Xna.Framework.Content.DictionaryReader`2[[System.String],[System.String]]")
            content += [0, 0, 0, 0]
            content += string("Microsoft.Xna.Framework.Content.StringReader")
            content += [0, 0, 0, 0]
            content += [0]                    // 0 ressource partagée
            content += [1]                    // racine = reader 1
            content += u32(entries.count)
            for (key, value) in entries { content += [2] + string(key) + [2] + string(value) }
            var header: [UInt8] = Array("XNB".utf8) + [UInt8(ascii: "w"), 5, 0x01]
            header += u32(10 + content.count)
            return Data(header + content)
        }
    }

    // MARK: - GlossarySource.resolve

    @Test func resolvePrefersXnbOverUnpacked() throws {
        let game = root
        defer { try? FileManager.default.removeItem(at: game) }
        try mkdirs([game.appendingPathComponent("Content/Strings"),
                    game.appendingPathComponent("Content (unpacked)/Strings")])
        try Fx.xnb(entries: [("a", "A")]).write(to: game.appendingPathComponent("Content/Strings/Objects.xnb"))
        try Data("{\"a\":\"A\"}".utf8).write(to: game.appendingPathComponent("Content (unpacked)/Strings/Objects.json"))
        guard case .xnbStrings? = GlossarySource.resolve(gameFolder: game) else {
            Issue.record("attendu .xnbStrings quand les deux existent")
            return
        }
    }

    @Test func resolveFallsBackToUnpacked() throws {
        let game = root
        defer { try? FileManager.default.removeItem(at: game) }
        let unpacked = game.appendingPathComponent("Content (unpacked)/Strings")
        try mkdirs([unpacked])
        try Data("{\"a\":\"A\"}".utf8).write(to: unpacked.appendingPathComponent("Objects.json"))
        guard case .unpackedStrings? = GlossarySource.resolve(gameFolder: game) else {
            Issue.record("attendu .unpackedStrings en l'absence de XNB")
            return
        }
    }

    @Test func resolveFindsMacOSBundleLayouts() throws {
        let base = root
        defer { try? FileManager.default.removeItem(at: base) }
        let strings = base.appendingPathComponent("Stardew Valley.app/Contents/Resources/Content/Strings")
        try mkdirs([strings])
        try Fx.xnb(entries: [("a", "A")]).write(to: strings.appendingPathComponent("Objects.xnb"))

        // Jeu configuré sur `…/Contents` :
        guard case .xnbStrings? = GlossarySource.resolve(
            gameFolder: base.appendingPathComponent("Stardew Valley.app/Contents")) else {
            Issue.record("attendu Resources/Content/Strings depuis Contents")
            return
        }
        // Jeu configuré sur `…/Contents/MacOS` (dossier de l'exécutable) :
        guard case .xnbStrings(let url)? = GlossarySource.resolve(
            gameFolder: base.appendingPathComponent("Stardew Valley.app/Contents/MacOS")) else {
            Issue.record("attendu ../Resources/Content/Strings depuis Contents/MacOS")
            return
        }
        #expect(url.path.contains("/Resources/Content/Strings"))
    }

    @Test func resolveIgnoresEmptyFoldersAndReturnsNil() throws {
        let game = root
        defer { try? FileManager.default.removeItem(at: game) }
        try mkdirs([game.appendingPathComponent("Content/Strings")])   // vide : pas une source
        #expect(GlossarySource.resolve(gameFolder: game) == nil)
        #expect(GlossarySource.resolve(gameFolder: root.appendingPathComponent("inexistant")) == nil)
    }

    // MARK: - GlossarySource.load

    @Test func loadReadsXnbAndLocalizedVariants() throws {
        let strings = root.appendingPathComponent("Strings")
        defer { try? FileManager.default.removeItem(at: root) }
        try mkdirs([strings])
        try Fx.xnb(entries: [("spring", "Spring")]).write(to: strings.appendingPathComponent("StringsFromCSFiles.xnb"))
        try Fx.xnb(entries: [("spring", "Printemps")]).write(to: strings.appendingPathComponent("StringsFromCSFiles.fr-FR.xnb"))
        let kind = GlossarySource.Kind.xnbStrings(strings)
        #expect(GlossarySource.load(asset: "StringsFromCSFiles", language: "", from: kind) == ["spring": "Spring"])
        #expect(GlossarySource.load(asset: "StringsFromCSFiles", language: "fr-FR", from: kind) == ["spring": "Printemps"])
        #expect(GlossarySource.load(asset: "Objects", language: "", from: kind) == nil)   // absent
    }

    @Test func loadReadsJsonInUnpackedFallback() throws {
        let strings = root.appendingPathComponent("unpacked/Strings")
        defer { try? FileManager.default.removeItem(at: root) }
        try mkdirs([strings])
        try Data("{\"spring\":\"Printemps\"}".utf8)
            .write(to: strings.appendingPathComponent("StringsFromCSFiles.fr-FR.json"))
        let kind = GlossarySource.Kind.unpackedStrings(strings)
        #expect(GlossarySource.load(asset: "StringsFromCSFiles", language: "fr-FR", from: kind)
                == ["spring": "Printemps"])
        #expect(GlossarySource.load(asset: "StringsFromCSFiles", language: "", from: kind) == nil)
    }

    // MARK: - GlossarySource.newestSourceDate

    @Test func newestSourceDateTakesTheMaxOfTheFolder() throws {
        let strings = root.appendingPathComponent("Strings")
        defer { try? FileManager.default.removeItem(at: root) }
        try mkdirs([strings])
        let english = strings.appendingPathComponent("Objects.xnb")
        let french = strings.appendingPathComponent("Objects.fr-FR.xnb")
        try Fx.xnb(entries: [("a", "A")]).write(to: english)
        try Fx.xnb(entries: [("a", "A FR")]).write(to: french)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 500)],
                                              ofItemAtPath: english.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 900)],
                                              ofItemAtPath: french.path)
        #expect(GlossarySource.newestSourceDate(of: .xnbStrings(strings))
                == Date(timeIntervalSince1970: 900))
    }

    // MARK: - GlossaryStore

    private let sample = Glossary(entries: [
        .init(en: "Iridium Ore", fr: "Minerai d'iridium", kind: .item),
        .init(en: "Spring", fr: "Printemps", kind: .season),
    ])

    @Test func saveLoadRoundTripIsIdentical() throws {
        let support = root
        defer { try? FileManager.default.removeItem(at: support) }
        try GlossaryStore.save(sample, language: "fr", appSupport: support)
        #expect(GlossaryStore.load(language: "fr", appSupport: support) == sample)
    }

    @Test func saveIsAtomicAndStoresTheDate() throws {
        let support = root
        defer { try? FileManager.default.removeItem(at: support) }
        try GlossaryStore.save(sample, language: "fr", appSupport: support)
        let files = try FileManager.default.contentsOfDirectory(
            atPath: support.appendingPathComponent("Glossary").path)
        #expect(files == ["fr.json"])   // pas de .tmp restant
        #expect(GlossaryStore.builtDate(language: "fr", appSupport: support) != nil)
    }

    @Test func loadWithoutCacheReturnsNil() throws {
        #expect(GlossaryStore.load(language: "fr", appSupport: root) == nil)
        #expect(GlossaryStore.builtDate(language: "fr", appSupport: root) == nil)
    }

    @Test func needsRebuildOnlyWhenSourcesAreStrictlyNewer() {
        let cached = Date(timeIntervalSince1970: 1000)
        #expect(GlossaryStore.needsRebuild(cachedAt: cached,
                                          sourcesNewerThan: Date(timeIntervalSince1970: 1001)))
        #expect(!GlossaryStore.needsRebuild(cachedAt: cached,
                                           sourcesNewerThan: Date(timeIntervalSince1970: 999)))
        #expect(!GlossaryStore.needsRebuild(cachedAt: cached, sourcesNewerThan: cached))
    }
}
