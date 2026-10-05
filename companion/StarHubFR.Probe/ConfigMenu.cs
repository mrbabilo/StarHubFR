using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// D4-T6 bis : les options de la sonde réglables **en jeu**, par le menu de
/// configuration générique (GMCM) — s'il est installé. Intégration faible :
/// l'API est résolue par réflexion sur l'objet rendu par
/// `IModRegistry.GetApi(string)` (référence d'assembly refusée — la sonde ne
/// déclare aucune dépendance, et GMCM absent = aucun menu, jamais une
/// panne). Effet des options : au **prochain lancement** du jeu (la config
/// est lue à l'`Entry`, dit dans les descriptions).
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
            var register = apiType.GetMethod("Register");
            var addBool = apiType.GetMethods()
                .FirstOrDefault(m => m.Name == "AddBoolOption" && m.GetParameters().Length == 5);
            if (register is null || addBool is null)
            {
                monitor.Log("Menu de configuration indisponible : API GMCM méconnaissable.", LogLevel.Trace);
                return;
            }

            register.Invoke(api, new object?[]
            {
                manifest,
                (Action)(() => config.Apply(new ModConfig())),
                (Action)(() => helper.WriteConfig(config)),
            });
            AddBool(addBool, api,
                () => config.MeasureHarmonyPatches,
                value => config.MeasureHarmonyPatches = value,
                "config.harmony");
            AddBool(addBool, api,
                () => config.MeasureTextures,
                value => config.MeasureTextures = value,
                "config.textures");
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
        addBool.Invoke(api, new object?[]
        {
            Manifest,
            get,
            set,
            (Func<string>)(() => Translations.Get(translationKey + ".name").Default(".")),
            (Func<string>?)(() => Translations.Get(translationKey + ".tooltip").Default(".")),
        });
    }
}
