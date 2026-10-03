import Foundation

/// **Quand** un mod écoute ses touches — ce qui décide si deux raccourcis
/// sur la même touche se gênent vraiment.
///
/// MCM et Keybind Radar (décompilés le 2026-10-03) comptent un conflit dès
/// que deux réglages portent la même combinaison : aucun ne connaît le
/// contexte. Or un raccourci lu seulement dans le menu propre d'un mod ne
/// croise jamais un raccourci lu seulement en jeu, et un raccourci qui exige
/// une touche d'activation non assignée ne se déclenche jamais.
///
/// Le savoir vient de la **lecture du code** de chaque mod (gestionnaire
/// `ButtonPressed`, ses gardes), consigné en ressource
/// (`assets/keybind-contexts.json`) — le même patron que `gmcm-options.json`.
/// Un mod absent de la table vaut `anywhere` : **seul un contexte relevé
/// retire un conflit**, jamais une supposition.
public struct KeybindContexts: Sendable, Equatable {

    public enum Context: String, Codable, Sendable {
        /// Aucune garde : le mod réagit partout, menus compris.
        case anywhere
        /// Joueur en jeu, aucun menu ouvert.
        case world
        /// Comme `world`, et jamais pendant un événement.
        case worldNoEvent
        /// Seulement dans un menu ouvert par le mod lui-même.
        case ownMenu
        /// Seulement dans un mode propre au mod (éditeur, vue), qui retient
        /// les touches pour le jeu.
        case ownMode
        /// Seulement pendant le rejeu d'un événement.
        case eventReplay

        /// Le contrôle du jeu `control` agit-il dans ce contexte ? Un mode
        /// propre retient toutes les touches ; dans un menu (ou un rejeu),
        /// le jeu n'écoute que ses contrôles de menu — et Chests Anywhere
        /// pose sa surcouche sur les menus de coffre du jeu.
        public func reaches(_ control: String) -> Bool {
            switch self {
            case .anywhere, .world, .worldNoEvent: true
            case .ownMode: false
            case .ownMenu, .eventReplay: Self.menuControls.contains(control)
            }
        }

        static let menuControls: Set<String> = ["menuButton", "cancelButton"]

        /// Deux réglages de **mods différents** peuvent-ils agir au même
        /// moment ? `anywhere` croise tout ; les contextes propres à un mod
        /// ne croisent que `anywhere`.
        public func overlaps(_ other: Context) -> Bool {
            switch (self, other) {
            case (.anywhere, _), (_, .anywhere): true
            case (.ownMenu, _), (_, .ownMenu), (.ownMode, _), (_, .ownMode): false
            case (.eventReplay, .eventReplay): true
            case (.eventReplay, _), (_, .eventReplay): false
            default: true // world / worldNoEvent entre eux
            }
        }
    }

    public struct Rule: Codable, Sendable, Equatable {
        /// Chemins de réglage visés (`"Controls.PrevChest"`) ; absent = tous
        /// les réglages du mod.
        public let keyPaths: [String]?
        public let context: Context?
        /// Le réglage n'agit qu'en maintenant cette autre touche du même
        /// fichier : si elle n'est assignée à rien, le réglage est **inerte** ;
        /// sinon il se juge comme la combinaison des deux (Alt + clic droit
        /// de Let's Move It) — le mod retient alors la touche pour le jeu.
        public let requires: String?
        /// Option booléenne du même fichier sans laquelle le réglage n'est
        /// jamais lu (`MenuOnMailbox` de Mailbox Menu) : à `false`, inerte.
        public let enabledBy: String?
        /// Option booléenne qui, à `true`, annule `requires` et `enabledBy`
        /// (`MultiSelect` de Let's Move It : le clic n'est plus retenu).
        public let unless: String?
        /// Touche de modification **maintenue** (lue par `IsDown`) dont le
        /// nom ne le dit pas : relevé dans le code.
        public let held: Bool?
        /// Ce que le code montre, pour la relecture (pas affiché).
        public let evidence: String?

        public init(keyPaths: [String]? = nil, context: Context? = nil, requires: String? = nil,
                    enabledBy: String? = nil, unless: String? = nil,
                    held: Bool? = nil, evidence: String? = nil) {
            self.keyPaths = keyPaths; self.context = context; self.requires = requires
            self.enabledBy = enabledBy; self.unless = unless
            self.held = held; self.evidence = evidence
        }
    }

    /// `UniqueID` plié → règles, la plus spécifique d'abord.
    private let rules: [String: [Rule]]

    public static let empty = KeybindContexts(rules: [:])

    public init(rules: [String: [Rule]]) {
        self.rules = Dictionary(rules.map { ($0.key.lowercased(), $0.value) },
                                uniquingKeysWith: { first, _ in first })
    }

    private struct File: Decodable { let mods: [String: [Rule]] }

    public init(data: Data) throws {
        self.init(rules: try JSONDecoder().decode(File.self, from: data).mods)
    }

    private func rule(_ uniqueId: String, _ keyPath: [String]) -> Rule? {
        guard let list = rules[uniqueId.lowercased()] else { return nil }
        let path = keyPath.joined(separator: ".")
        return list.first { $0.keyPaths?.contains(path) == true }
            ?? list.first { $0.keyPaths == nil }
    }

    public func isHeld(uniqueId: String, keyPath: [String]) -> Bool {
        rule(uniqueId, keyPath)?.held == true
    }

    public func context(uniqueId: String, keyPath: [String]) -> Context {
        rule(uniqueId, keyPath)?.context ?? .anywhere
    }

    /// Inerte : l'option qui l'active est à `false`, ou la touche
    /// d'activation exigée existe dans le fichier et n'est assignée à rien
    /// (`None`, vide). Absente ou illisible : on ne sait pas — pas inerte.
    public func isInert(uniqueId: String, keyPath: [String],
                        leaves: [ConfigEditorModel.Leaf]) -> Bool {
        guard let rule = conditional(uniqueId, keyPath, leaves) else { return false }
        if let option = rule.enabledBy, Self.bool(option, in: leaves) == false { return true }
        guard let combos = required(rule, leaves) else { return false }
        return combos.allSatisfy(\.isEmpty)
    }

    /// La touche à maintenir pour que le réglage agisse, quand elle est
    /// assignée : le réglage se juge alors en combinaison avec elle.
    public func chord(uniqueId: String, keyPath: [String],
                      leaves: [ConfigEditorModel.Leaf]) -> [KeybindCombo] {
        guard let rule = conditional(uniqueId, keyPath, leaves) else { return [] }
        return (required(rule, leaves) ?? []).filter { !$0.isEmpty }
    }

    /// Chaque combinaison du réglage unie à chaque combinaison de l'accord.
    public static func chorded(_ combos: [KeybindCombo], with chord: [KeybindCombo]) -> [KeybindCombo] {
        guard !chord.isEmpty else { return combos }
        return combos.flatMap { combo in
            combo.isEmpty ? [combo]
                : chord.compactMap { KeybindCombo(buttons: combo.buttons + $0.buttons) }
        }
    }

    /// La règle, sauf si son option `unless` est vraie dans le fichier.
    private func conditional(_ uniqueId: String, _ keyPath: [String],
                             _ leaves: [ConfigEditorModel.Leaf]) -> Rule? {
        guard let rule = rule(uniqueId, keyPath) else { return nil }
        if let option = rule.unless, Self.bool(option, in: leaves) == true { return nil }
        return rule
    }

    private func required(_ rule: Rule, _ leaves: [ConfigEditorModel.Leaf]) -> [KeybindCombo]? {
        guard let required = rule.requires,
              let leaf = leaves.first(where: { $0.keyPath.joined(separator: ".") == required })
        else { return nil }
        return KeybindParser.parse(leaf.value)
    }

    /// Une option booléenne du fichier ; `nil` si absente ou d'un autre type.
    static func bool(_ path: String, in leaves: [ConfigEditorModel.Leaf]) -> Bool? {
        guard let leaf = leaves.first(where: { $0.keyPath.joined(separator: ".") == path }) else { return nil }
        switch leaf.value {
        case .bool(let value): return value
        case .string(let text): return Bool(text.lowercased())
        default: return nil
        }
    }
}
