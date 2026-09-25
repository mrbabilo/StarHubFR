import Foundation

/// Un raccourci tel que l'écran d'aide le montre : ses touches, dans l'ordre
/// où on les presse, et ce qu'il fait.
public struct ShortcutEntry: Identifiable, Equatable, Sendable {
    /// Glyphes macOS (« ⌘ », « ⇧ », « ↩ »…) ou lettres. Plusieurs entrées =
    /// une combinaison ; `ShortcutEntry.or` sépare deux variantes (et ne se
    /// confond pas avec la touche « / » de ⌘/).
    public let keys: [String]
    public static let or = "|"
    public let labelKey: String
    public var id: String { keys.joined() + labelKey }

    public init(_ keys: [String], _ labelKey: String) {
        self.keys = keys
        self.labelKey = labelKey
    }
}

public struct ShortcutGroup: Identifiable, Equatable, Sendable {
    public let titleKey: String
    public let entries: [ShortcutEntry]
    public var id: String { titleKey }
}

/// Tous les raccourcis de l'app, pour l'écran d'aide — **la liste qu'il
/// affiche**, pas celle qui les câble.
///
/// Les raccourcis eux-mêmes restent là où ils agissent (menu « Aller »,
/// `SearchFieldShortcut`, `ModListView+Keyboard`, palette). Ce catalogue ne
/// peut donc pas les imposer ; il évite seulement de les recopier quand une
/// source existe : ⌘1…⌘9 sont lus dans `SidebarOrder`, comme le menu
/// « Aller ». Un raccourci ajouté ailleurs doit être ajouté ici — le test
/// `KeyboardShortcutCatalogTests` en fige la liste pour que l'oubli se voie
/// à la relecture du diff.
public enum KeyboardShortcutCatalog {
    public static let helpKey = "/"

    public static func groups() -> [ShortcutGroup] {
        let screens = (1...9).compactMap { n -> ShortcutEntry? in
            guard let entry = SidebarOrder.entry(forShortcut: n) else { return nil }
            return ShortcutEntry(["⌘", "\(n)"], entry.labelKey)
        }
        return [
            ShortcutGroup(titleKey: L10n.Shortcuts.groupScreens, entries: screens),
            ShortcutGroup(titleKey: L10n.Shortcuts.groupNavigation, entries: [
                ShortcutEntry(["⌘", "K"], L10n.Shortcuts.palette),
                ShortcutEntry(["⌘", "F"], L10n.Shortcuts.search),
                ShortcutEntry(["⇥", ShortcutEntry.or, "⇧", "⇥"], L10n.Shortcuts.tab),
                ShortcutEntry(["⌘", helpKey], L10n.Shortcuts.help),
            ]),
            ShortcutGroup(titleKey: L10n.Shortcuts.groupModList, entries: [
                ShortcutEntry(["↑", ShortcutEntry.or, "↓"], L10n.Shortcuts.listMove),
                ShortcutEntry(["↖", ShortcutEntry.or, "↘"], L10n.Shortcuts.listEnds),
                ShortcutEntry(["↩"], L10n.Shortcuts.listOpen),
            ]),
            ShortcutGroup(titleKey: L10n.Shortcuts.groupPalette, entries: [
                ShortcutEntry(["↑", ShortcutEntry.or, "↓"], L10n.Shortcuts.paletteMove),
                ShortcutEntry(["↩"], L10n.Shortcuts.paletteGo),
                ShortcutEntry(["⎋"], L10n.Main.close),
            ]),
            ShortcutGroup(titleKey: L10n.Shortcuts.groupDialogs, entries: [
                ShortcutEntry(["↩"], L10n.Shortcuts.confirm),
                ShortcutEntry(["⎋"], L10n.Shortcuts.cancel),
            ]),
            ShortcutGroup(titleKey: L10n.Shortcuts.groupApp, entries: [
                ShortcutEntry(["⌘", "H"], L10n.Shortcuts.hide),
                ShortcutEntry(["⌘", "M"], L10n.Shortcuts.minimize),
                ShortcutEntry(["⌘", "Q"], L10n.Shortcuts.quit),
            ]),
        ]
    }
}
