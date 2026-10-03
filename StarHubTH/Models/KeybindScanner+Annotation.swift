import Foundation

public extension KeybindScanner {

    /// L'annotation « lié à » d'une rangée raccourci de l'éditeur de
    /// config (C4-T10 suite — reproduction de l'écran de MCM 2.1.2, qui
    /// note chaque réglage « Conflicts with {mod} ({réglage}) » ou
    /// « Conflicts with default game controls »). La nôtre lit le rapport
    /// déjà calculé : mêmes exclusions (catalogues, remap, modificateurs,
    /// réglages inertes, contextes relevés), même normalisation
    /// (`KeybindCombo`).
    struct KeybindRowAnnotation: Equatable, Sendable {
        public struct OtherUse: Equatable, Sendable {
            public let modName: String
            /// Le chemin du réglage en face, tel que le rapport le porte
            /// (`["Controls", "SearchMenuPreviewChest"]`) — la clé brute du
            /// fichier, pas le libellé.
            public let settingKey: [String]
            public init(modName: String, settingKey: [String]) {
                self.modName = modName
                self.settingKey = settingKey
            }
        }
        /// Le contrôle du jeu visé (`"toolbarSwap"`), quand la combinaison
        /// est à bouton unique et retombe sur un contrôle par défaut. Un
        /// mod de remap n'en reçoit pas : poser le contrôle est sa
        /// fonction (C4-T9).
        public let gameControl: String?
        /// Les autres mods dont une liaison porte **exactement** cette
        /// combinaison et agit au même moment (collisions clavier et manette).
        public let conflicts: [OtherUse]
        public var isEmpty: Bool { gameControl == nil && conflicts.isEmpty }
        public init(gameControl: String? = nil, conflicts: [OtherUse] = []) {
            self.gameControl = gameControl
            self.conflicts = conflicts
        }
    }

    /// L'annotation pour la rangée `keyPath` du mod `modID` (l'id du
    /// **dossier**, celui de `ModScan.id`) portant `combo`.
    static func annotation(for combo: KeybindCombo,
                           ofMod modID: String,
                           keyPath: [String] = [],
                           in report: KeybindReport) -> KeybindRowAnnotation {
        // Les deux exclusions du rapport, appliquées à la valeur de la rangée
        // — y compris une touche qu'on vient de capturer (C4-T12).
        let key = settingKey(modID, keyPath)
        if isHeldModifier(combo, keyPath: keyPath, declared: report.heldSettings.contains(key))
            || report.inertSettings.contains(key) {
            return KeybindRowAnnotation()
        }
        let context = report.context(of: modID, keyPath)
        // Une touche à maintenir : la rangée se juge en combinaison, comme
        // au rapport (Alt + clic droit ne heurte pas l'action du jeu).
        let combo = KeybindContexts.chorded([combo], with: report.settingChords[key] ?? []).first ?? combo
        var gameControl: String? = nil
        if combo.buttons.count == 1, let button = combo.buttons.first,
           !report.remapModIDs.contains(modID),
           !vanillaRemapModIds.contains(modID.lowercased()) {
            gameControl = report.gameControls
                .first { $0.buttons.contains(button) && context.reaches($0.name) }?.name
        }
        // Toutes les liaisons actives, pas les seules collisions : pour une
        // valeur du fichier, le résultat est le même (partagée avec un autre
        // mod = collision) ; pour une touche qu'on vient de capturer (C4-T12),
        // c'est la seule façon de voir l'unique autre mod qui la porte.
        // Même tri que les collisions (nom, puis id : homonymes réels).
        let conflicts = (report.activeUses[combo] ?? [])
            .filter { $0.modID != modID && context.overlaps(report.context(of: $0.modID, $0.keyPath)) }
            .sorted { ($0.modName, $0.modID) < ($1.modName, $1.modID) }
            .map { KeybindRowAnnotation.OtherUse(modName: $0.modName, settingKey: $0.keyPath) }
        return KeybindRowAnnotation(gameControl: gameControl, conflicts: conflicts)
    }

    /// Une touche de modification **maintenue** : partagée normalement,
    /// hors conflits. Il faut le nom du réglage (« Modifier », « ModKey »)
    /// ou un relevé du code (`held`) — Let's Move It ouvre son menu sur
    /// Alt droite seul (`ModMenuKey`, `JustPressed`) : là, Alt est une
    /// touche comme une autre (relevé 2026-10-03).
    static func isHeldModifier(_ combo: KeybindCombo, keyPath: [String], declared: Bool) -> Bool {
        guard combo.isModifierOnly else { return false }
        if declared { return true }
        let name = (keyPath.last ?? "").lowercased()
        return name.contains("modifier")
            || name.range(of: #"^modkey\d*$"#, options: .regularExpression) != nil
    }

    /// La clé d'un réglage dans `settingContexts` / `inertSettings`.
    static func settingKey(_ modID: String, _ keyPath: [String]) -> String {
        modID + "\u{1F}" + keyPath.joined(separator: ".")
    }
}

public extension KeybindScanner.KeybindReport {
    /// Le contexte d'écoute relevé pour un réglage, `anywhere` par défaut.
    func context(of modID: String, _ keyPath: [String]) -> KeybindContexts.Context {
        settingContexts[KeybindScanner.settingKey(modID, keyPath)] ?? .anywhere
    }
}

extension KeybindCombo {
    /// Les touches de modification que l'on **maintient** (Ctrl, Maj, Alt,
    /// ⌘/Windows) — noms `SButton`.
    static let heldModifiers: Set<String> = [
        "LeftShift", "RightShift", "LeftControl", "RightControl",
        "LeftAlt", "RightAlt", "LeftWindows", "RightWindows",
    ]

    /// Combinaison faite **uniquement** de touches de modification : la
    /// partager est l'usage normal (MCM l'écarte aussi des contrôles du jeu).
    public var isModifierOnly: Bool {
        !buttons.isEmpty && buttons.allSatisfy { Self.heldModifiers.contains($0) }
    }
}
