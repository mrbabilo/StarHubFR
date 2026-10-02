import Testing
import Foundation
@testable import StarHubTHCore

/// La vue clavier du rapport de raccourcis : géométrie des claviers Mac, et
/// placement des réglages par nom de bouton.
struct KeybindKeyboardModelTests {

    // MARK: - Géométrie

    /// Chaque rangée fait exactement la largeur du clavier, sans trou ni
    /// chevauchement (hors flèches haut/bas, empilées sur la même colonne).
    @Test(arguments: [MacKeyboardGeometry.Kind.iso, .ansi])
    func everyRowFillsTheBoard(kind: MacKeyboardGeometry.Kind) {
        let keys = MacKeyboardGeometry.keys(kind)
        for row in 0...5 {
            let inRow = keys.filter { $0.row == row && $0.shape != .halfBottom }
                .sorted { $0.x < $1.x }
            var x = 0.0
            for key in inRow {
                #expect(abs(key.x - x) < 0.001, "rangée \(row) : trou ou chevauchement à x=\(key.x)")
                x = key.x + key.width
            }
            // L'Entrée ISO occupe aussi la rangée 3 par son pied.
            if !(kind == .iso && row == 3) {
                #expect(abs(x - MacKeyboardGeometry.width) < 0.001, "rangée \(row) finit à \(x)")
            }
        }
    }

    /// L'ISO porte la touche de plus (`kVK_ISO_Section`), l'ANSI non ; aucun
    /// keyCode n'est dessiné deux fois.
    @Test func isoHasTheSectionKeyAndNoDuplicates() {
        let iso = MacKeyboardGeometry.keys(.iso).compactMap(\.keyCode)
        let ansi = MacKeyboardGeometry.keys(.ansi).compactMap(\.keyCode)
        #expect(iso.contains(0x0A))
        #expect(!ansi.contains(0x0A))
        #expect(Set(iso).count == iso.count)
        #expect(Set(ansi).count == ansi.count)
    }

    /// Chaque touche dessinée qui porte un keyCode a un nom que la capture
    /// sait produire — sinon la vue montrerait une touche que l'éditeur ne
    /// sait pas écrire. Les touches à caractère prennent ici une lettre
    /// témoin ; elles se nomment à l'exécution par la disposition.
    @Test func everyDrawnKeyCodeIsNameable() {
        for key in MacKeyboardGeometry.keys(.iso) {
            guard let code = key.keyCode else { continue }
            let name = MacKeyCodeMap.capturedName(keyCode: code, character: "a")
            #expect(name != nil, "keyCode \(code) sans nom")
        }
    }

    // MARK: - Placement

    private func setting(_ id: String, _ key: String, _ buttons: [[String]],
                         conflict: Bool = false) -> KeybindScanner.SettingBinding {
        .init(modID: id, modName: id, keyPath: [key],
              combos: buttons.map { KeybindCombo(buttons: $0)! }, hasConflict: conflict)
    }

    @Test func modifiersDoNotTakeTheKey() {
        let index = KeybindDevicePlacement.index([setting("ui", "Board", [["LeftControl", "Q"]])])
        #expect(index.keys.sorted() == ["Q"])
    }

    /// Le cas voisin : un réglage réduit à un modificateur reste visible.
    @Test func aModifierAloneSitsOnItsKey() {
        let index = KeybindDevicePlacement.index([setting("run", "SprintKey", [["LeftShift"]])])
        #expect(index.keys.sorted() == ["LeftShift"])
    }

    @Test func everyMainKeyOfAComboGetsTheSetting() {
        let index = KeybindDevicePlacement.index([setting("m", "K", [["F8"], ["LeftShoulder"]])])
        #expect(index.keys.sorted() == ["F8", "LeftShoulder"])
    }

    @Test func unassignedSettingsArePlacedNowhere() {
        let index = KeybindDevicePlacement.index([setting("m", "K", [])])
        #expect(index.isEmpty)
    }

    /// Le conflit est celui du rapport, pas « deux mods sur la touche ».
    @Test func conflictComesFromTheReport() {
        let index = KeybindDevicePlacement.index([
            setting("a", "Plain", [["Q"]]),
            setting("b", "WithCtrl", [["LeftControl", "Q"]]),
        ])
        #expect(index["Q"]?.count == 2)
        #expect(!KeybindDevicePlacement.hasConflict("Q", in: index))
        let real = KeybindDevicePlacement.index([setting("a", "K", [["G"]], conflict: true)])
        #expect(KeybindDevicePlacement.hasConflict("G", in: real))
    }

    /// Invariant : tout réglage lié est soit posé sur une surface, soit dans
    /// les restes — aucun ne disparaît.
    @Test func nothingIsLost() {
        let settings = [
            setting("a", "K1", [["Q"]]), setting("b", "K2", [["Delete"]]),
            setting("c", "K3", [["MouseLeft"]]), setting("d", "K4", [["LeftShoulder"]]),
        ]
        let index = KeybindDevicePlacement.index(settings)
        let placed: Set<String> = ["Q", "MouseLeft", "LeftShoulder"]
        let leftovers = KeybindDevicePlacement.leftovers(of: index, placed: placed)
        #expect(leftovers == ["Delete"])
        let covered = Set(index.filter { placed.contains($0.key) || leftovers.contains($0.key) }
            .values.flatMap { $0.map(\.id) })
        #expect(covered == Set(settings.map(\.id)))
    }

    @Test func surfaceNamesAreRealSButtonNames() {
        for name in KeybindDevicePlacement.mouseButtons + KeybindDevicePlacement.gamepadButtons
            + Array(KeybindDevicePlacement.modifierNames) {
            #expect(SButtonTable.canonicalName(for: name) == name, "« \(name) »")
        }
    }
}
