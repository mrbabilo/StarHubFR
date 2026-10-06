import Testing
import Foundation
@testable import StarHubTHCore

/// D2-T3 §6 — les deux formes relevées dans le vrai journal (spec §2,
/// textes exacts du 2026-10-06). Le nom du mod vient du crochet de source
/// SMAPI (`LogEntry.modName`), pas du message.
struct ConfigMenuCoverageTests {

    private func entry(_ message: String, mod: String?) -> LogEntry {
        LogEntry(timestamp: "18:56:10", message: message, level: .trace,
                 source: .smapi, modName: mod)
    }

    @Test func modernConfigMenuForm() {
        let found = ConfigMenuCoverage.coverage(in: [entry(
            "Registered config menu for Modern Config Menu (palmhacker13.ModernConfigMenu).",
            mod: "Modern Config Menu")])
        #expect(found.count == 1)
        #expect(found[0].name == "Modern Config Menu")
        #expect(found[0].modId == "palmhacker13.ModernConfigMenu")
        #expect(found[0].flavor == .mcm)
    }

    @Test func gmcmFormNameFromSource() {
        let found = ConfigMenuCoverage.coverage(in: [entry(
            "Registered with Generic Mod Config Menu.",
            mod: "互动气泡 Interaction Bubbles")])
        #expect(found.count == 1)
        #expect(found[0].name == "互动气泡 Interaction Bubbles")
        #expect(found[0].modId == nil)
        #expect(found[0].flavor == .gmcm)
    }

    @Test func gmcmWithoutModNameSkipped() {
        let found = ConfigMenuCoverage.coverage(in: [entry(
            "Registered with Generic Mod Config Menu.", mod: nil)])
        #expect(found.isEmpty)
    }

    @Test func duplicatesCollapsedByIdThenName() {
        let entries = [
            entry("Registered config menu for Modern Config Menu (palmhacker13.ModernConfigMenu).", mod: nil),
            entry("Registered config menu for Modern Config Menu (palmhacker13.ModernConfigMenu).", mod: nil),
            entry("Registered with Generic Mod Config Menu.", mod: "Interaction Bubbles"),
            entry("Registered with Generic Mod Config Menu.", mod: "Interaction Bubbles"),
        ]
        let found = ConfigMenuCoverage.coverage(in: entries)
        #expect(found.count == 2)
    }

    @Test func mcmNameWithInnerParenthesesKeepsLastGroupAsId() {
        // Le DERNIER groupe parenthésé final est l'ID (spec §3.2) : un nom
        // qui contient déjà des parenthèses ne doit pas casser le découpage.
        let found = ConfigMenuCoverage.coverage(in: [entry(
            "Registered config menu for Widget (beta) (some.Widget).", mod: nil)])
        #expect(found.count == 1)
        #expect(found[0].name == "Widget (beta)")
        #expect(found[0].modId == "some.Widget")
    }

    @Test func lookalikesRejected() {
        let entries = [
            // Forme MCM sans ID parenthésé final : pas collée.
            entry("Registered config menu for Widget.", mod: nil),
            // GMCM sans le point final : pas la forme mesurée.
            entry("Registered with Generic Mod Config Menu", mod: "X"),
            // Ligne de conflit qui ressemble : ignorée.
            entry("Two content packs want to load the 'Portraits/Haley' asset.", mod: "Content Patcher"),
        ]
        #expect(ConfigMenuCoverage.coverage(in: entries).isEmpty)
    }

    @Test func sortedByName() {
        let entries = [
            entry("Registered with Generic Mod Config Menu.", mod: "Zebra Mod"),
            entry("Registered with Generic Mod Config Menu.", mod: "Alpha Mod"),
        ]
        let found = ConfigMenuCoverage.coverage(in: entries)
        #expect(found.map(\.name) == ["Alpha Mod", "Zebra Mod"])
    }
}
