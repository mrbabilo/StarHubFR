namespace StarHubFR.Probe;

/// <summary>
/// Quand réécrire `gmcm-options.json` : le registre de GMCM est figé après
/// `GameLaunched` (les mods s'y inscrivent au lancement) et la langue ne
/// bouge pas en cours de partie — même registre et même langue, l'export de
/// 4,4 Mo ne se réécrit pas à chaque chargement de sauvegarde. Pur : rien de
/// SMAPI, testé hors jeu.
/// </summary>
public static class GmcmExportRule
{
    public static bool ShouldWrite(int? exportedMods, string? exportedLanguage,
                                   int registryMods, string language, bool force) =>
        force || exportedMods != registryMods || exportedLanguage != language;

    /// <summary>
    /// Le genre d'option GMCM d'un réglage de ModernConfigMenu (MCM 2.3.4,
    /// `SettingBase` et ses sous-classes) : ceux que l'app lit déjà dans
    /// `gmcm-options.json`. Un mod qui trouve MCM s'y inscrit **au lieu de**
    /// GMCM (PureBinarySave, UltraSmooth) ; sans ça, ses libellés et ses aides
    /// n'arrivaient jamais à l'éditeur. `null` : rien à régler.
    /// </summary>
    public static string? McmKind(string settingType) => settingType switch
    {
        "ToggleSetting" or "TextboxSetting" or "KeybindSetting" or "ColorPickerSetting" => "SimpleModOption",
        "SliderSetting" => "NumericModOption",
        "DropdownSetting" => "ChoiceModOption",
        _ => null,
    };
}
