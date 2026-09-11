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
        "deepLFallbackEnabled", "defaultProfileId", "didSeedDefaultProfile",
        "disabledModsMigratedToDotPrefix",
        "discoveryHideInstalled", "favoriteMods", "gameDir", "installDateGraceFolders",
        "installedModRegistry", "installedModRegistryBackup", "keepNexusArchives",
        "launchProfile", "localAIBaseURL", "localAIModel", "modActivationTimestamps",
        "modListViewMode", "modProfiles", "modUpdateSnoozes", "modVersionAnchors",
        "modsListLayout", "nexusAccount", "nexusCachedCategories",
        "nexusCachedExtras", "nexusCachedUpdates", "nexusCustomCategories",
        "nexusCustomModIds", "nexusLastCheckAt", "nexusQuota", "nexusUpdatesLastCheckedAt",
        "profileConfigsDesyncedProfileId", "profileManagedConfigMods",
        "registryMigrationV2Done", "showDeveloperLogs", "showThaiTranslationHub",
        "starhubFR.releaseLastCheckedAt", "starhubFR.releaseLastKnown",
        "starhubFR.releaseLastSeenTag",
    ]

    /// Le domaine de l'application d'origine, dont le fork a hérité jusqu'au
    /// 2026-09-10.
    public static let legacyDomain = "com.appleboiy.StarHubTH"

    /// Marqueur de reprise, posé dans le **nouveau** domaine. Délibérément
    /// **hors `ownedKeys`** : il décrit l'installation courante, pas une donnée
    /// à hériter — le recopier ferait croire à une reprise déjà faite.
    public static let completionMarker = "starhubFR.legacyDefaultsImported"

    /// La reprise, **une fois par installation**.
    ///
    /// Sans ce garde, la recopie rejouait à chaque lancement — et toute clé que
    /// l'app efface volontairement revenait d'entre les morts : `activeProfileId`
    /// à la désélection d'un profil (`StarHubTHViewModel`, branche `else` du
    /// chemin normal), les quatre caches Nexus qu'on purge
    /// (`NexusUpdateChecker`), et le registre d'installation purgé pour
    /// corruption — remplacé par la copie périmée de l'ancien domaine.
    ///
    /// Le marqueur est posé **inconditionnellement**, y compris quand il n'y a
    /// rien à reprendre : une installation neuve doit être « déjà à jour », pas
    /// éternellement candidate.
    ///
    /// - Returns: combien de clés ont été reprises (0 aux lancements suivants).
    @discardableResult
    public static func importLegacyIfNeeded(from source: UserDefaults?,
                                            to destination: UserDefaults,
                                            keys: [String] = ownedKeys) -> Int {
        guard !destination.bool(forKey: completionMarker) else { return 0 }
        defer { destination.set(true, forKey: completionMarker) }
        guard let source else { return 0 }
        return copy(from: source, to: destination, keys: keys)
    }

    /// La reprise du processus courant, évaluée **une seule fois** quel que soit
    /// le nombre d'appelants.
    ///
    /// Elle est déclenchée de deux endroits — `AppSupport.resolve()` et
    /// `StarHubTHApp` — et c'est délibéré. L'ordre des initialisateurs de
    /// propriétés de `StarHubTHApp` **ne doit pas être porteur** : ce serait
    /// une affirmation statique, du genre que ce dépôt a déjà payé. Depuis le
    /// passage des préférences IA/DeepL en propriétés **stockées** (miroirs du
    /// chantier `@Observable`, 2026-09-11), ce ne sont plus des lectures
    /// calculées : ce sont des initialisateurs de propriété qui lisent
    /// `UserDefaults` directement. Deux garanties tiennent l'antériorité :
    /// l'App déclenche `runOnce` avant de construire le ViewModel
    /// (`bootstrapDefaults`, initialisateur de propriété de `StarHubTHApp`,
    /// donc avant son `init` qui construit le VM), et au sein du VM le premier
    /// lecteur defaults reste `modCompatibility` (L114) — toute nouvelle
    /// propriété liseuse defaults déclarée AVANT lui serait semée de valeurs
    /// pré-migration. Le second appel ne coûte rien.
    public static let runOnce: Void = {
        let copied = importLegacyIfNeeded(from: UserDefaults(suiteName: legacyDomain),
                                          to: .standard)
        if copied > 0 {
            NSLog("StarHubFR : %lu préférence(s) reprises de l'installation précédente",
                  copied)
        }
    }()

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
