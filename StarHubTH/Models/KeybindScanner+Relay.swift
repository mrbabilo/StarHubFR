import Foundation

/// Ce que l'analyse dit des touches **rejouées** (`KeybindContexts.Rule.emitted`) :
/// les mods qui en portent, nommés en pied de rapport parce qu'elles sont
/// sorties des collisions, et les relais morts.
public struct KeybindRelays: Equatable, Sendable {
    /// Un bouton dont la combinaison n'est liée par aucun mod actif : il ne
    /// déclenchera rien (mod ciblé en pause, touche changée depuis).
    public struct Dead: Hashable, Sendable {
        public let modID: String, modName: String, keyPath: [String], combo: KeybindCombo
    }
    public var emittingMods: [String] = []
    public var dead: [Dead] = []
}

extension KeybindScanner {
    /// Relais des mods **actifs** : un mod en pause ne rejoue rien. Un relais
    /// vit si un autre mod actif lie la même combinaison (`activeUses` du
    /// rapport, d'où les touches rejouées sont déjà absentes).
    public static func relays(mods: [ModScan], contexts: KeybindContexts,
                              activeUses: [KeybindCombo: [ModUse]]) -> KeybindRelays {
        var out = KeybindRelays()
        for mod in mods where mod.isActive {
            var emits = false
            for leaf in ConfigEditorModel.leaves(of: mod.tree)
            where contexts.isEmitted(uniqueId: mod.lookupKey, keyPath: leaf.keyPath) {
                guard case .keybind(let combos) = classify(leaf: leaf) else { continue }
                emits = true
                for combo in combos where !combo.isEmpty
                && !(activeUses[combo] ?? []).contains(where: { $0.modID != mod.id }) {
                    out.dead.append(.init(modID: mod.id, modName: mod.name,
                                          keyPath: leaf.keyPath, combo: combo))
                }
            }
            if emits { out.emittingMods.append(mod.name) }
        }
        out.emittingMods.sort()
        out.dead.sort { ($0.modName, $0.combo) < ($1.modName, $1.combo) }
        return out
    }
}
