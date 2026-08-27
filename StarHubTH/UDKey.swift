import Foundation

/// Centralized `UserDefaults` keys for the app.
///
/// Use these constants instead of raw string literals so a typo can never
/// silently write to a different key (and so renames are caught at compile
/// time). Keys that are owned by a single module (e.g. Nexus caches in
/// `NexusUpdateChecker`) stay private to that module — only keys shared
/// across files are exposed here.
public enum UDKey {
    /// Folder path of the user's Stardew Valley install.
    public static let gameDir = "gameDir"
    /// Active UI language code (`"en"` / `"fr"` / `"th"`).
    public static let currentLanguage = "currentLanguage"
    /// When `true`, toggling a mod on/off also toggles its SMAPI dependencies
    /// (and optionally its content-pack children) in the same operation.
    public static let chainToggleDependencies = "chainToggleDependencies"
    /// Last used launch profile name (`"SMAPI"` / `"Vanilla"` / ...).
    public static let launchProfile = "launchProfile"
    /// Whether to quit StarHubTH right after launching the game.
    public static let closeAfterLaunch = "closeAfterLaunch"
    /// JSON-encoded list of `ModProfile` (named mod enable/disable sets).
    public static let modProfiles = "modProfiles"
    /// UUID string of the currently active `ModProfile`, or `nil` for the
    /// implicit "everything" profile.
    public static let activeProfileId = "activeProfileId"
    /// Registry of installed mods (JSON-encoded) — used for same-version
    /// update detection and restored from backup on corruption.
    public static let installedModRegistry = "installedModRegistry"
    /// Auto-backup of `installedModRegistry`, written whenever the registry
    /// itself is updated. Restored if the primary is detected as corrupt.
    public static let installedModRegistryBackup = "installedModRegistryBackup"
    /// Whether to automatically check Nexus Mods for updates after startup.
    public static let autoCheckNexusUpdates = "autoCheckNexusUpdates"
    /// One-shot flag: `true` once the `Mods_disabled/` → `Mods/.X` migration
    /// has run on this machine. Removed in the release after the one that
    /// introduces the dot-prefix toggle (N+1) — see the plan's step 17.
    public static let disabledModsMigratedToDotPrefix = "disabledModsMigratedToDotPrefix"
    /// Base URL of the local LLM server (Ollama / LM Studio) for assisted
    /// translation — loopback only, validated by `LocalLLMEndpoint`.
    public static let localAIBaseURL = "localAIBaseURL"
    /// Model name used for assisted translation requests.
    public static let localAIModel = "localAIModel"
    /// Autorise le secours en ligne quand l'IA locale échoue — ou quand il
    /// n'y en a aucune. Décoché par défaut : rien ne sort de la machine sans
    /// ce geste. La clé, elle, vit au trousseau (`KeychainSecret`).
    public static let deepLFallbackEnabled = "deepLFallbackEnabled"
    /// Les mods dont le `config.json` suit le profil actif (B3-T5), par nom
    /// **logique** de dossier. Encodé en JSON comme `favoriteMods`.
    public static let profileManagedConfigMods = "profileManagedConfigMods"
    /// Le profil actif dont le disque ne porte **pas** les configs (B3-T5) :
    /// une bascule faite jeu ouvert a sauté la moitié configs. Vide sinon.
    /// Persisté : quitter l'app entre les deux bascules ramènerait le trou.
    public static let profileConfigsDesyncedProfileId = "profileConfigsDesyncedProfileId"
}
