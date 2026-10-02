import Foundation

/// Les contrôles du jeu et leurs boutons **par défaut**, figés du relevé IL
/// du constructeur `StardewValley.Options` (tâche 0, step 3). Ce ne sont pas
/// les contrôles réels de l'utilisateur — la réserve est affichée à l'écran.
public enum GameControlDefaults {
    public struct GameControl: Equatable, Sendable {
        public let name: String
        public let buttons: [String]
        public init(name: String, buttons: [String]) { self.name = name; self.buttons = buttons }
    }
    /// ── coller le relevé de la tâche 0 (step 3) : un `GameControl` par
    /// champ `InputButton[]` du constructeur d'`Options`, tous. ──
    public static let controls: [GameControl] = [
        GameControl(name: "moveUpButton", buttons: ["W"]),
        GameControl(name: "moveDownButton", buttons: ["S"]),
        GameControl(name: "moveLeftButton", buttons: ["A"]),
        GameControl(name: "moveRightButton", buttons: ["D"]),
        GameControl(name: "actionButton", buttons: ["X", "MouseRight"]),
        GameControl(name: "cancelButton", buttons: ["V"]),
        GameControl(name: "useToolButton", buttons: ["C", "MouseLeft"]),
        GameControl(name: "menuButton", buttons: ["E", "Escape"]),
        GameControl(name: "runButton", buttons: ["LeftShift"]),
        GameControl(name: "chatButton", buttons: ["T", "OemQuestion"]),
        GameControl(name: "mapButton", buttons: ["M"]),
        GameControl(name: "journalButton", buttons: ["F"]),
        GameControl(name: "inventorySlot1", buttons: ["D1"]),
        GameControl(name: "inventorySlot2", buttons: ["D2"]),
        GameControl(name: "inventorySlot3", buttons: ["D3"]),
        GameControl(name: "inventorySlot4", buttons: ["D4"]),
        GameControl(name: "inventorySlot5", buttons: ["D5"]),
        GameControl(name: "inventorySlot6", buttons: ["D6"]),
        GameControl(name: "inventorySlot7", buttons: ["D7"]),
        GameControl(name: "inventorySlot8", buttons: ["D8"]),
        GameControl(name: "inventorySlot9", buttons: ["D9"]),
        GameControl(name: "inventorySlot10", buttons: ["D0"]),
        GameControl(name: "inventorySlot11", buttons: ["OemMinus"]),
        GameControl(name: "inventorySlot12", buttons: ["OemPlus"]),
        GameControl(name: "toolbarSwap", buttons: ["Tab"]),
        GameControl(name: "emoteButton", buttons: ["Y"]),
    ]
}
