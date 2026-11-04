using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

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

    /// <summary>
    /// Cette classe décrit-elle ce `config.json` ? Au moins 80 % des clés de
    /// premier niveau y sont des membres, sans la casse. C'est la condition
    /// pour lancer son constructeur (C4-T18) : une classe croisée dans le code
    /// d'un getter n'est pas forcément une config, et un constructeur peut
    /// avoir des effets.
    /// </summary>
    public static bool CoversConfig(IEnumerable<string> members, string? configJson)
    {
        if (configJson is null) return false;
        try
        {
            using JsonDocument document = JsonDocument.Parse(configJson);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return false;
            var known = new HashSet<string>(members, StringComparer.OrdinalIgnoreCase);
            var keys = document.RootElement.EnumerateObject().Select(key => key.Name).ToList();
            return keys.Count > 0 && keys.Count(known.Contains) >= keys.Count * 0.8;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    /// <summary>
    /// La propriété qui lit la valeur d'un réglage MCM. `KeybindSetting` porte
    /// aussi un `Get`, réduit au premier bouton de la liste : `config.json`
    /// garde la liste entière, c'est elle qu'il faut comparer.
    /// </summary>
    public static string McmGetter(string settingType) => settingType switch
    {
        "KeybindSetting" => "GetKeybindList",
        "ColorPickerSetting" => "Getter",
        _ => "Get",
    };
}
