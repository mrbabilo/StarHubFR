using System;
using System.Reflection;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// D4-T6 bis : les options de la sonde réglables **en jeu**, par le menu de
/// configuration générique (GMCM) — s'il est installé. Appelé à
/// `GameLaunched`, quand SMAPI autorise enfin les API de mods. Intégration faible :
/// l'API est résolue par réflexion sur l'objet rendu par
/// `IModRegistry.GetApi(string)` (référence d'assembly refusée — la sonde ne
/// déclare aucune dépendance, et GMCM absent = aucun menu, jamais une
/// panne). Effet des options : au **prochain lancement** du jeu pour les deux
/// mesures, lues à l'`Entry` ; tout de suite pour les mini-stats, relues à
/// chaque tick (dit dans les descriptions).
///
/// Le miroir lecture/défauts vit dans `ProbeConfigMirror` (testé) ; ce
/// fichier ne porte que le câblage GMCM, hors test.
/// </summary>
internal static class ConfigMenu
{
    private static IMonitor Monitor = null!;
    private static IManifest Manifest = null!;
    private static ITranslationHelper Translations = null!;

    public static void Initialize(IModHelper helper, IMonitor monitor, ModConfig config, IManifest manifest)
    {
        Monitor = monitor;
        Manifest = manifest;
        Translations = helper.Translation;
        try
        {
            object? api = helper.ModRegistry.GetApi("spacechase0.GenericModConfigMenu");
            if (api is null)
            {
                monitor.Log("Menu de configuration indisponible : GMCM absent.", LogLevel.Trace);
                return;
            }
            var apiType = api.GetType();
            var register = GmcmCall.Find(apiType, "Register", 4);
            var addBool = GmcmCall.Find(apiType, "AddBoolOption", 5);
            if (register is null || addBool is null)
            {
                monitor.Log("Menu de configuration indisponible : API GMCM méconnaissable.", LogLevel.Trace);
                return;
            }

            // titleScreenOnly à false : GMCM le met à true par défaut, et ces
            // options se règlent aussi partie chargée.
            GmcmCall.Invoke(register, api, new object?[]
            {
                manifest,
                (Action)(() => config.Apply(new ModConfig())),
                (Action)(() => helper.WriteConfig(config)),
                false,
            });
            AddBool(addBool, api,
                () => config.MeasureHarmonyPatches,
                value => config.MeasureHarmonyPatches = value,
                "config.measureHarmonyPatches");
            AddBool(addBool, api,
                () => config.MeasureTextures,
                value => config.MeasureTextures = value,
                "config.measureTextures");
            AddBool(addBool, api,
                () => config.ShowMiniStats,
                value => config.ShowMiniStats = value,
                "config.showMiniStats");
            monitor.Log("Menu de configuration GMCM posé.", LogLevel.Trace);
        }
        catch (Exception ex)
        {
            monitor.Log($"Menu de configuration non posé : {ex.Message}", LogLevel.Trace);
        }
    }

    private static void AddBool(MethodInfo addBool, object api,
        Func<bool> get, Action<bool> set, string translationKey)
    {
        GmcmCall.Invoke(addBool, api, new object?[]
        {
            Manifest,
            get,
            set,
            (Func<string>)(() => Translations.Get(translationKey + ".name").Default(".")),
            (Func<string>?)(() => Translations.Get(translationKey + ".tooltip").Default(".")),
        });
    }
}
