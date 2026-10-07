import Foundation

/// Une ligne de la section « Extensions principales » des réglages : un mod
/// dont l'app a besoin, ou que la plupart des parcs portent, avec d'où
/// l'installer.
///
/// L'état se lit par `UniqueID` (`ModPresence`), jamais par le nom : une
/// traduction porte souvent le nom du mod qu'elle traduit, et la recherche
/// par mot l'aurait prise pour lui.
public struct AppExtension: Equatable, Sendable {
    public enum Group: Equatable, Sendable {
        /// Une fonction de l'app ne marche pas sans lui.
        case requiredByApp
        /// Les frameworks et l'extension que la plupart des parcs portent.
        case common
    }

    public enum Source: Equatable, Sendable {
        /// Page Nexus : « Mod Manager Download » renvoie un `nxm://` à l'app.
        case nexus(Int)
        /// Livré avec SMAPI : le réinstaller le remet en place.
        case smapi
        /// Livré dans l'app (`ProbeBundle`).
        case app
    }

    public let uniqueId: String
    public let name: String
    public let source: Source
    public let group: Group
    /// Utile mais pas indispensable : la fonction marche sans, en moins bien.
    public let recommended: Bool
    /// Clé de localisation de la phrase « à quoi il sert ».
    public let purposeKey: String

    /// L'onglet Fichiers de la page Nexus, là où se trouve « Mod Manager
    /// Download ».
    public var installURL: URL? {
        guard case .nexus(let id) = source else { return nil }
        return MissingDependencies.filesPage(nexusId: id)
    }

    public func presence(in mods: [ModItem]) -> ModPresence {
        ModPresence.resolve(uniqueId: uniqueId, in: mods)
    }

    /// Identifiants Nexus relevés dans les manifestes du parc le 2026-10-07 ;
    /// SVE écrit `Nexus:???`, son 3753 vient de la liste de compatibilité de
    /// SMAPI (`mods.jsonc`).
    public static let catalog: [AppExtension] = [
        AppExtension(uniqueId: "SMAPI.SaveBackup", name: "SaveBackup", source: .smapi,
                     group: .requiredByApp, recommended: false, purposeKey: "ext_purpose_save_backup"),
        AppExtension(uniqueId: "SMAPI.ConsoleCommands", name: "ConsoleCommands", source: .smapi,
                     group: .requiredByApp, recommended: false, purposeKey: "ext_purpose_console_commands"),
        AppExtension(uniqueId: ModPresence.probeId, name: "StarHubFR Probe", source: .app,
                     group: .requiredByApp, recommended: false, purposeKey: "ext_purpose_probe"),
        AppExtension(uniqueId: SloDiagnosticContract.uniqueId, name: "Stardew Loading Optimizer",
                     source: .nexus(SloDiagnosticContract.nexusId),
                     group: .requiredByApp, recommended: false, purposeKey: "ext_purpose_slo"),
        AppExtension(uniqueId: PerformanceDiagnosticKind.stardropium.uniqueId, name: "Stardropium",
                     source: .nexus(PerformanceDiagnosticKind.stardropium.nexusId),
                     group: .requiredByApp, recommended: false, purposeKey: "ext_purpose_stardropium"),
        AppExtension(uniqueId: "spacechase0.GenericModConfigMenu", name: "Generic Mod Config Menu",
                     source: .nexus(5098), group: .requiredByApp, recommended: true,
                     purposeKey: "ext_purpose_gmcm"),
        AppExtension(uniqueId: "Pathoschild.ContentPatcher", name: "Content Patcher", source: .nexus(1915),
                     group: .common, recommended: false, purposeKey: "ext_purpose_content_patcher"),
        AppExtension(uniqueId: "spacechase0.SpaceCore", name: "SpaceCore", source: .nexus(1348),
                     group: .common, recommended: false, purposeKey: "ext_purpose_spacecore"),
        AppExtension(uniqueId: "FlashShifter.StardewValleyExpandedCP", name: "Stardew Valley Expanded",
                     source: .nexus(3753), group: .common, recommended: false, purposeKey: "ext_purpose_sve"),
    ]
}
