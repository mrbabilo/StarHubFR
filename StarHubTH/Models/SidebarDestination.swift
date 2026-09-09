import Foundation

/// Une page de l'application — l'onglet couramment affiché par `MainView`.
///
/// **Pourquoi un type et pas une `String`.** Jusqu'au 2026-09-09, l'onglet
/// courant était une chaîne et la répartition du contenu une suite de
/// `if currentTab == "Mods"`. Une faute de frappe n'y cassait pas la
/// compilation : elle rendait une **page blanche, en silence**. Le `switch`
/// de `MainView` est désormais **exhaustif** sur ce type — ajouter une
/// destination sans lui donner de page devient une erreur de build.
///
/// ⚠️ **Ne jamais ajouter de `default:`** aux `switch` qui couvrent ce type
/// (répartition du contenu, titre de fenêtre) : ce serait rouvrir exactement
/// le trou qu'il ferme. Même règle que `SettingsSectionOrder.sectionView`.
///
/// La `rawValue` reprend à l'identique les chaînes d'avant la migration :
/// elle sert au journal et au diagnostic, jamais à choisir une page.
public enum SidebarDestination: String, Equatable, Sendable {
    /// Hors groupe : la carte de compte, en tête de la barre latérale.
    case home = "Home"

    // BIBLIOTHÈQUE.
    case mods = "Mods"
    case discover = "Discover"
    case updates = "Updates"

    // PARTIES.
    case profiles = "Profiles"
    case saves = "Saves"

    // SANTÉ & SECOURS.
    case systemAlerts = "SystemAlerts"
    case quarantine = "Quarantine"
    case installBackups = "InstallBackups"
    case configBackups = "ConfigBackups"
    case maintenance = "Maintenance"

    // APPLICATION.
    case logs = "Logs"
    case settings = "Settings"
    case appChangelog = "AppChangelog"
    case thaiHub = "ThaiHub"
}
