import Foundation

/// Où poser chaque réglage de raccourci sur la vue clavier / souris /
/// manette du rapport : par **nom de bouton** `SButton`.
///
/// Trois règles, chacune testée :
/// - les modificateurs d'une combinaison ne prennent pas la touche :
///   `LeftControl + Q` va sur Q, sinon Ctrl deviendrait la touche la plus
///   chargée du clavier ;
/// - le cas voisin : un réglage **réduit** à un modificateur (Maj pour
///   courir) va sur la touche du modificateur — il ne s'évapore pas ;
/// - une combinaison à plusieurs touches principales va sur chacune.
///
/// Le conflit d'une touche est celui du rapport (`SettingBinding.hasConflict`,
/// le périmètre de `problemCount`) — pas une seconde règle « deux mods sur
/// la même touche », qui compterait en conflit `Q` et `Ctrl + Q`.
public enum KeybindDevicePlacement {

    public static let modifierNames: Set<String> = [
        "LeftShift", "RightShift", "LeftControl", "RightControl",
        "LeftAlt", "RightAlt", "LeftWindows", "RightWindows",
    ]

    public static let mouseButtons = ["MouseLeft", "MouseRight", "MouseMiddle", "MouseX1", "MouseX2"]

    public static let gamepadButtons = [
        "LeftTrigger", "RightTrigger", "LeftShoulder", "RightShoulder",
        "LeftStick", "RightStick", "DPadUp", "DPadDown", "DPadLeft", "DPadRight",
        "ControllerBack", "ControllerStart", "BigButton",
        "ControllerA", "ControllerB", "ControllerX", "ControllerY",
    ]

    /// Nom de bouton → réglages posés dessus, dans l'ordre du rapport. Un
    /// réglage non assigné n'est posé nulle part.
    public static func index(_ settings: [KeybindScanner.SettingBinding])
        -> [String: [KeybindScanner.SettingBinding]] {
        var out: [String: [KeybindScanner.SettingBinding]] = [:]
        for setting in settings where !setting.isUnassigned {
            var names: [String] = []
            for combo in setting.combos {
                let main = combo.buttons.filter { !modifierNames.contains($0) }
                for name in (main.isEmpty ? combo.buttons : main) where !names.contains(name) {
                    names.append(name)
                }
            }
            for name in names { out[name, default: []].append(setting) }
        }
        return out
    }

    /// Les noms qu'aucune surface dessinée ne porte (`Delete`, `Home` sur un
    /// MacBook, une ponctuation absente de la disposition courante) — ils
    /// s'affichent à part, jamais perdus.
    public static func leftovers(of index: [String: [KeybindScanner.SettingBinding]],
                                 placed: Set<String>) -> [String] {
        index.keys.filter { !placed.contains($0) }.sorted()
    }

    /// Un nom porte-t-il un conflit avéré ?
    public static func hasConflict(_ name: String,
                                   in index: [String: [KeybindScanner.SettingBinding]]) -> Bool {
        index[name]?.contains(where: \.hasConflict) ?? false
    }
}
