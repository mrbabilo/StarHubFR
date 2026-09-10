import Foundation

/// La recopie des préférences quand l'identifiant de bundle change.
///
/// Changer `CFBundleIdentifier` change le domaine `UserDefaults` : l'app neuve
/// ne verrait plus rien de ce que l'ancienne avait écrit.
///
/// **La liste est une mesure, pas une mémoire.** Le plan du 2026-08-26 en
/// comptait 31 ; le domaine réel (`defaults read com.appleboiy.StarHubTH`,
/// 99 entrées tout bruit AppKit déduit) en porte 40 au 2026-09-10 — neuf nées
/// depuis (`blacklistedMods`, `modUpdateSnoozes`, `modsListLayout`,
/// `nexusUpdatesLastCheckedAt`, `keepNexusArchives`, `discoveryHideInstalled`,
/// `profileManagedConfigMods`, et les deux `starhubFR.*`). S'y ajoutent les
/// clés déclarées dans `UDKey` ou en `@AppStorage` pas encore écrites sur la
/// machine de référence (`chainToggleDependencies`, `profileConfigsDesyncedProfileId`,
/// `installDateGraceFolders`, `starhubFR.releaseLastSeenTag`,
/// `showThaiTranslationHub`) : la recopie doit les couvrir le jour où elles
/// existent.
///
/// **`AppleLanguages` est exclue à dessein** : l'app la re-dérive de
/// `currentLanguage` après la recopie (`StarHubTHApp`), et la recopier
/// figerait le choix de langue de l'installation précédente.
///
/// Les clés d'état de fenêtre d'AppKit (`NSWindow Frame …`, `NSSplitView
/// Subview Frames …`) ne sont **pas** recopiées : elles se reconstruisent
/// seules, et elles portent le nom du module dans leur clé.
public enum DefaultsMigration {
    /// Les clés que l'application possède, et qu'elle perdrait sans recopie.
    public static let ownedKeys: [String] = [
        "SaveNotes_v2", "activeProfileId", "appColorScheme", "autoCheckNexusUpdates",
        "blacklistedMods", "chainToggleDependencies", "closeAfterLaunch", "currentLanguage",
        "deepLFallbackEnabled", "didSeedDefaultProfile", "disabledModsMigratedToDotPrefix",
        "discoveryHideInstalled", "favoriteMods", "gameDir", "installDateGraceFolders",
        "installedModRegistry", "installedModRegistryBackup", "keepNexusArchives",
        "launchProfile", "localAIBaseURL", "localAIModel", "modActivationTimestamps",
        "modListViewMode", "modProfiles", "modUpdateSnoozes", "modVersionAnchors",
        "modsListLayout", "nexusAccount", "nexusApiKey", "nexusCachedCategories",
        "nexusCachedExtras", "nexusCachedUpdates", "nexusCustomCategories",
        "nexusCustomModIds", "nexusLastCheckAt", "nexusQuota", "nexusUpdatesLastCheckedAt",
        "profileConfigsDesyncedProfileId", "profileManagedConfigMods",
        "registryMigrationV2Done", "showDeveloperLogs", "showThaiTranslationHub",
        "starhubFR.releaseLastCheckedAt", "starhubFR.releaseLastKnown",
        "starhubFR.releaseLastSeenTag",
    ]

    /// Recopie les clés absentes de la destination. **Jamais d'écrasement** :
    /// une valeur déjà présente côté destination est plus récente que celle de
    /// la source, par construction.
    ///
    /// - Returns: combien de clés ont été recopiées.
    @discardableResult
    public static func copy(from source: UserDefaults, to destination: UserDefaults,
                            keys: [String]) -> Int {
        var copied = 0
        for key in keys {
            guard destination.object(forKey: key) == nil,
                  let value = source.object(forKey: key) else { continue }
            destination.set(value, forKey: key)
            copied += 1
        }
        return copied
    }
}
