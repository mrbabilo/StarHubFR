import Testing
import Foundation
@testable import StarHubTHCore

/// Les contrôles réels du joueur (2026-10-03) : `default_options` (dernière
/// partie jouée), `startup_preferences` en secours, défauts sinon.
struct GameControlPreferencesTests {
    /// Extrait du vrai `default_options` du parc : GCSR a vidé la touche de
    /// l'action et de l'outil (souris gardée) et posé ZQSD.
    private let lastGame = #"""
    <?xml version="1.0" encoding="utf-8"?><Options xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><autoRun>true</autoRun>\#
    <actionButton><InputButton><key>None</key><mouseLeft>false</mouseLeft><mouseRight>false</mouseRight></InputButton><InputButton><key>None</key><mouseLeft>false</mouseLeft><mouseRight>true</mouseRight></InputButton></actionButton>\#
    <useToolButton><InputButton><key>None</key><mouseLeft>false</mouseLeft><mouseRight>false</mouseRight></InputButton><InputButton><key>None</key><mouseLeft>true</mouseLeft><mouseRight>false</mouseRight></InputButton></useToolButton>\#
    <moveUpButton><InputButton><key>Z</key><mouseLeft>false</mouseLeft><mouseRight>false</mouseRight></InputButton></moveUpButton>\#
    <inventorySlot2><InputButton><key>None</key><mouseLeft>false</mouseLeft><mouseRight>false</mouseRight></InputButton></inventorySlot2>\#
    <menuButton><InputButton><key>E</key><mouseLeft>false</mouseLeft><mouseRight>false</mouseRight></InputButton><InputButton><key>Escape</key><mouseLeft>false</mouseLeft><mouseRight>false</mouseRight></InputButton></menuButton></Options>
    """#

    private func control(_ name: String, _ controls: [GameControlDefaults.GameControl]) -> [String]? {
        controls.first { $0.name == name }?.buttons
    }

    @Test func readsTheLastGameControls() throws {
        let controls = try #require(GameControlPreferences.controls(fromXML: Data(lastGame.utf8)))
        #expect(control("actionButton", controls) == ["MouseRight"])
        #expect(control("useToolButton", controls) == ["MouseLeft"])
        #expect(control("moveUpButton", controls) == ["Z"])
        #expect(control("inventorySlot2", controls) == [])
        #expect(control("menuButton", controls) == ["E", "Escape"])
        // Absent du fichier : la valeur par défaut tient.
        #expect(control("inventorySlot3", controls) == ["D3"])
        #expect(controls.map(\.name) == GameControlDefaults.controls.map(\.name))
    }

    @Test func aFileWithoutControlsIsNotRead() {
        #expect(GameControlPreferences.controls(fromXML: Data("<Options><autoRun>true</autoRun></Options>".utf8)) == nil)
        #expect(GameControlPreferences.controls(fromXML: Data("pas du XML <".utf8)) == nil)
    }

    /// `startup_preferences` range ses contrôles sous `<clientOptions>`.
    @Test func loadPrefersTheLastGameThenStartupPreferences() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(GameControlPreferences.load(appDataFolder: dir).source == .defaults)

        let startup = "<StartupPreferences><clientOptions><moveUpButton><InputButton><key>W</key>"
            + "<mouseLeft>false</mouseLeft><mouseRight>false</mouseRight></InputButton></moveUpButton>"
            + "</clientOptions></StartupPreferences>"
        try Data(startup.utf8).write(to: dir.appendingPathComponent("startup_preferences"))
        #expect(GameControlPreferences.load(appDataFolder: dir).source == .startupPreferences)

        try Data(lastGame.utf8).write(to: dir.appendingPathComponent("default_options"))
        let loaded = GameControlPreferences.load(appDataFolder: dir)
        #expect(loaded.source == .lastGame)
        #expect(control("moveUpButton", loaded.controls) == ["Z"])
    }

    /// Le rapport juge contre les contrôles qu'on lui passe : une barre
    /// d'objets sans touche ne heurte plus le 2 d'un mod.
    @Test func reportJudgesAgainstTheGivenControls() throws {
        let controls = try #require(GameControlPreferences.controls(fromXML: Data(lastGame.utf8)))
        let mod = KeybindScanner.ModScan(id: "m", name: "m", isActive: true,
                                         tree: .object(ConfigJSONTree.Object([("MenuKey", .string("D2"))])))
        #expect(KeybindScanner.report(mods: [mod]).gameConflicts.map(\.control.name) == ["inventorySlot2"])
        #expect(KeybindScanner.report(mods: [mod], gameControls: controls).gameConflicts.isEmpty)
    }
}
