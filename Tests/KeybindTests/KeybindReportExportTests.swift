import Testing
import Foundation
@testable import StarHubTHCore

/// C4-T13 — le rapport en Markdown : les problèmes y sont, l'inventaire
/// table les réglages par mod, et un rapport propre n'écrit pas de
/// sections vides.
struct KeybindReportExportTests {
    private func tree(_ pairs: [(String, ConfigJSONTree.Value)]) -> ConfigJSONTree.Value {
        .object(ConfigJSONTree.Object(pairs))
    }
    private func mod(_ id: String, _ name: String, active: Bool = true,
                     _ pairs: [(String, ConfigJSONTree.Value)]) -> KeybindScanner.ModScan {
        .init(id: id, name: name, isActive: active, tree: tree(pairs))
    }

    @Test func markdownListsCollisionAndInventory() {
        let r = KeybindScanner.report(mods: [
            mod("a", "Alpha", [("Hotkey", .string("F8")), ("SilentKey", .string("None"))]),
            mod("b", "Beta", [("Hotkey", .string("F8"))]),
        ])
        let md = KeybindReportExport.markdown(
            report: r, generatedAt: Date(timeIntervalSince1970: 0))
        #expect(md.contains("# Rapport des raccourcis"))
        #expect(md.contains("2 raccourcis liés"))
        #expect(md.contains("## Collisions clavier"))
        #expect(md.contains("**F8** — Alpha (`Hotkey`), Beta (`Hotkey`)"))
        #expect(md.contains("## Tous les réglages liés"))
        #expect(md.contains("| Alpha | `SilentKey` | None | non assigné |"))
        #expect(md.contains("| Beta | `Hotkey` | F8 | conflit |"))
        #expect(md.contains("généré le 1970-01-01"))
    }

    /// Un mod en pause porte sa mention — il ne tire pas au jeu.
    @Test func pausedModIsNamedAsSuch() {
        let r = KeybindScanner.report(mods: [
            mod("a", "Alpha", [("Key", .string("F7"))]),
            mod("b", "Zzz", active: false, [("Key", .string("F7"))]),
        ])
        let md = KeybindReportExport.markdown(report: r, generatedAt: Date())
        #expect(md.contains("## Collisions latentes"))
        #expect(md.contains("Zzz (en pause, `Key`)"))
    }

    /// La même honnêteté que l'écran : pas de section vide.
    @Test func cleanReportHasNoEmptySections() {
        let r = KeybindScanner.report(mods: [mod("a", "Alpha", [("Key", .string("F7"))])])
        let md = KeybindReportExport.markdown(report: r, generatedAt: Date())
        #expect(!md.contains("## Collisions"))
        #expect(!md.contains("## Co-déclenchements"))
        #expect(md.contains("## Tous les réglages liés"))
    }
}
