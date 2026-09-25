import Foundation

/// Le groupe sous lequel une destination se lit dans la barre latérale.
///
/// `top` n'est pas un groupe dessiné : c'est l'Accueil, porté par la carte de
/// compte en tête de colonne. Il est nommé ici parce que le menu « Aller » et
/// la palette ⌘K en ont besoin — la barre, elle, ne le rend pas.
public enum SidebarGroup: String, CaseIterable, Sendable {
    case top
    case library, saves, health, app
    /// Pas un groupe dessiné non plus : un bouton du pied épinglé
    /// (`ChangelogFooterButton`). Même raison que `top` d'être ici.
    case footer
}

/// Une **ligne** de la barre : la destination plus ce qu'il faut pour la
/// dessiner.
///
/// L'identité est `SidebarDestination` (F7) — c'est elle qui garantit qu'une
/// page existe, par le `switch` exhaustif de `MainView`. Cette structure ne
/// porte que l'habillage.
public struct SidebarEntry: Identifiable, Equatable, Sendable {
    public let destination: SidebarDestination
    public let icon: String
    public let labelKey: String
    public let group: SidebarGroup
    public var id: SidebarDestination { destination }

    public init(_ destination: SidebarDestination, icon: String,
                labelKey: String, group: SidebarGroup) {
        self.destination = destination
        self.icon = icon
        self.labelKey = labelKey
        self.group = group
    }
}

/// L'ordre des destinations — **la source unique**.
///
/// La barre latérale, le menu « Aller » et la palette le lisent tous les
/// trois ; l'écrire une seule fois est ce qui empêche les trois de diverger au
/// premier ajout de destination.
///
/// Précédent suivi : `SettingsSectionOrder` (H-T7), même forme, même raison.
public enum SidebarOrder {

    /// Toutes les destinations, dans l'ordre de l'écran.
    ///
    /// Ordre figé par un test de non-régression : le modifier ici décale
    /// ⌘1…⌘9. Les commentaires qui portent le *pourquoi* d'une entrée vivaient
    /// dans `SidebarNavGroups` ; ils décrivent la donnée, ils vivent ici.
    public static let all: [SidebarEntry] = [
        // Hors groupe : la carte de compte, première à l'écran — d'où ⌘1.
        SidebarEntry(.home, icon: "house.fill",
                     labelKey: L10n.Main.home, group: .top),

        // BIBLIOTHÈQUE — l'usage quotidien.
        SidebarEntry(.mods, icon: "puzzlepiece.extension.fill",
                     labelKey: L10n.Mods.mods, group: .library),
        SidebarEntry(.discover, icon: "safari.fill",
                     labelKey: L10n.Main.discover, group: .library),
        // Toujours visible, même à zéro : sans l'entrée, plus moyen de
        // déclencher une vérification Nexus à la main.
        SidebarEntry(.updates, icon: "arrow.triangle.2.circlepath",
                     labelKey: L10n.Main.modUpdates, group: .library),
        // C5-T1 — remplace l'entrée du hub thaï, toujours visible : la page
        // dit elle-même quand rien n'a encore été cherché.
        SidebarEntry(.frenchTranslations, icon: "character.bubble.fill",
                     labelKey: L10n.FrTranslations.title, group: .library),

        // PARTIES.
        SidebarEntry(.profiles, icon: "person.2.fill",
                     labelKey: L10n.Profiles.title, group: .saves),
        SidebarEntry(.saves, icon: "folder.fill",
                     labelKey: L10n.Saves.saves, group: .saves),

        // SANTÉ & SECOURS — ce qui répare et ce qui prévient.
        // Atteignable au vert aussi : la page porte « Revérifier le journal »,
        // et un journal muet avant une installation ne dit rien de l'après.
        SidebarEntry(.systemAlerts, icon: "exclamationmark.triangle.fill",
                     labelKey: L10n.Main.systemAlerts, group: .health),
        // Idem : l'entrée n'apparaissait autrefois qu'avec des éléments en
        // quarantaine — cachant la page précisément quand on veut lancer
        // l'analyse et la voir ne rien trouver.
        SidebarEntry(.quarantine, icon: "tray.full.fill",
                     labelKey: L10n.Main.quarantine, group: .health),
        // I-T8 — une entrée pour les trois segments ; placée après la
        // quarantaine pour que ⌘8 et ⌘9 ne bougent pas.
        SidebarEntry(.backups, icon: "arrow.uturn.backward.circle.fill",
                     labelKey: L10n.ModInstall.manageBackups, group: .health),
        SidebarEntry(.maintenance, icon: "internaldrive",
                     labelKey: L10n.Maintenance.title, group: .health),

        // APPLICATION.
        SidebarEntry(.logs, icon: "terminal.fill",
                     labelKey: L10n.Logs.logs, group: .app),
        SidebarEntry(.settings, icon: "gearshape.fill",
                     labelKey: L10n.Settings.settings, group: .app),
        // Au pied de la barre, en bouton (2026-09-25) : dernière de la
        // liste, elle n'avait pas de raccourci à céder.
        SidebarEntry(.appChangelog, icon: "doc.text.fill",
                     labelKey: L10n.Main.appChangelog, group: .footer),
    ]

    public static func entries(in group: SidebarGroup) -> [SidebarEntry] {
        all.filter { $0.group == group }
    }

    /// Le numéro de raccourci d'une destination : 1…9 pour les neuf
    /// premières, `nil` au-delà. On compte à l'écran — toutes les entrées sont
    /// visibles depuis le retrait du hub thaï (C5-T1).
    public static func shortcutIndex(of destination: SidebarDestination) -> Int? {
        guard let i = all.firstIndex(where: { $0.destination == destination }),
              i < 9 else { return nil }
        return i + 1
    }

    /// L'inverse. Hors de 1…9 : `nil`, jamais un débordement.
    public static func entry(forShortcut index: Int) -> SidebarEntry? {
        guard (1...9).contains(index), index <= all.count else { return nil }
        return all[index - 1]
    }
}
