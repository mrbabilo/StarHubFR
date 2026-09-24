import Foundation

/// C4-T13 — la vue « tous les raccourcis » : chaque réglage de raccourci des
/// mods actifs, pas seulement ceux qui posent problème. Keybind Radar
/// n'existe que pour cette liste, et MCM a son `KeybindOverviewModal`.
///
/// Mesuré sur le parc le 2026-09-24 : 176 réglages sur 48 mods — 108 liés
/// (égal à `keybindCount`, invariant testé), 68 à `None` (CJB Cheats Menu,
/// Let's Move It… : de vrais `"None"` dans le fichier), zéro chaîne vide
/// sous un nom de raccourci. Les règles de classement (R1–R4) restent
/// celles de `KeybindScanner.report` : les lignes naissent dans sa boucle,
/// mêmes exclusions (catalogues écartés, mods en pause absents).
extension KeybindScanner {

    /// Un réglage de raccourci d'un mod actif. Identité `(modID, keyPath)` :
    /// jamais le chemin joint (`["a.b"]` et `["a", "b"]` se confondraient),
    /// jamais le nom (Swim est installé deux fois sur ce parc).
    public struct SettingBinding: Identifiable, Hashable, Sendable {
        public struct ID: Hashable, Sendable {
            public let modID: String
            public let keyPath: [String]
        }
        public let modID: String
        public let modName: String
        public let keyPath: [String]
        /// Les combinaisons **qui lient** : `None` retiré. Vide = réglage
        /// non assigné.
        public let combos: [KeybindCombo]
        /// En collision (clavier ou manette) avec un autre mod actif, ou sur
        /// un contrôle du jeu. Même périmètre que `problemCount` : ni les
        /// co-déclenchements ni le latent, qui ne sont pas des problèmes
        /// avérés (C4-T7).
        public let hasConflict: Bool

        public var id: ID { ID(modID: modID, keyPath: keyPath) }
        public var isUnassigned: Bool { combos.isEmpty }

        public init(modID: String, modName: String, keyPath: [String],
                    combos: [KeybindCombo], hasConflict: Bool) {
            self.modID = modID; self.modName = modName; self.keyPath = keyPath
            self.combos = combos; self.hasConflict = hasConflict
        }
    }

    public enum OverviewFilter: String, CaseIterable, Sendable {
        case all, bound, conflicts, unassigned

        public func admits(_ binding: SettingBinding) -> Bool {
            switch self {
            case .all: return true
            case .bound: return !binding.isUnassigned
            case .conflicts: return binding.hasConflict
            case .unassigned: return binding.isUnassigned
            }
        }
    }

    /// Les lignes de la vue d'ensemble, marquées. `settings` porte les
    /// réglages bruts collectés par `report` ; le statut de conflit se lit
    /// sur les usages des problèmes avérés, calculés après la boucle.
    static func markConflicts(
        _ settings: [(modID: String, modName: String, keyPath: [String], combos: [KeybindCombo])],
        collisions: [KeybindCollision], gameConflicts: [GameControlConflict]
    ) -> [SettingBinding] {
        var conflicting = Set<SettingBinding.ID>()
        for use in collisions.flatMap(\.uses) + gameConflicts.flatMap(\.uses) {
            conflicting.insert(.init(modID: use.modID, keyPath: use.keyPath))
        }
        return settings
            .map { s in
                SettingBinding(modID: s.modID, modName: s.modName, keyPath: s.keyPath,
                               combos: s.combos,
                               hasConflict: conflicting.contains(.init(modID: s.modID, keyPath: s.keyPath)))
            }
            // Départage par `modID` : le nom seul n'ordonne pas totalement
            // (homonymes), et le tri de Swift n'est pas stable.
            .sorted { ($0.modName, $0.modID, $0.keyPath.joined(separator: "\u{1}"))
                    < ($1.modName, $1.modID, $1.keyPath.joined(separator: "\u{1}")) }
    }

    /// Filtre puis recherche. La recherche ignore casse et accents, et
    /// porte sur le nom du mod, le chemin du réglage et les touches
    /// affichées — ce que la ligne montre, rien d'autre.
    public static func overview(_ bindings: [SettingBinding], filter: OverviewFilter,
                                query: String) -> [SettingBinding] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return bindings.filter { binding in
            guard filter.admits(binding) else { return false }
            guard !needle.isEmpty else { return true }
            let haystack = [binding.modName, binding.keyPath.joined(separator: ".")]
                + binding.combos.map(\.display)
            return haystack.contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
