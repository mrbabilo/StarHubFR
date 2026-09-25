using System;
using System.IO;
using System.Linq;
using HarmonyLib;
using StardewModdingAPI;
using StardewModdingAPI.Events;

namespace StarHubFR.Probe;

/// <summary>
/// Mod d'observation de StarHubFR (essai du 2026-09-26). Il ne modifie aucun
/// comportement du jeu : il lit la carte des patches Harmony et mesure les
/// temps de trame, puis écrit des fichiers JSON que l'app lit.
///
/// Sortie : ~/.config/StardewValley/ModData/mrbabilo.StarHubFR.Probe/
///  - harmony-map.json   la carte des patches, réécrite à chaque étape
///  - timings.jsonl      une ligne par minute de jeu réelle
/// </summary>
public sealed class ModEntry : Mod
{
    internal static string OutputDir = "";

    public override void Entry(IModHelper helper)
    {
        OutputDir = Path.Combine(Constants.DataPath, "ModData", ModManifest.UniqueID);
        Directory.CreateDirectory(OutputDir);

        var harmony = new Harmony(ModManifest.UniqueID);
        FrameTimings.Initialize(harmony, Monitor);
        GcPauses.Start(Monitor);

        // La carte se relève deux fois : après l'Entry de tous les mods, puis
        // au chargement de la sauvegarde — certains mods patchent tard (modules
        // activés à la demande, intégrations posées quand l'autre mod répond).
        helper.Events.GameLoop.GameLaunched += (_, _) =>
        {
            FrameTimings.LoadedMods = helper.ModRegistry.GetAll().Count();
            HarmonyMap.Write(helper, Monitor, "GameLaunched");
        };
        helper.Events.GameLoop.SaveLoaded += (_, _) => HarmonyMap.Write(helper, Monitor, "SaveLoaded");

        helper.ConsoleCommands.Add("starhubfr_probe",
            "Écrit la carte Harmony et la minute de mesures en cours.",
            (_, _) =>
            {
                Monitor.Log(FrameTimings.Status(), LogLevel.Info);
                HarmonyMap.Write(helper, Monitor, "Console");
                FrameTimings.FlushNow();
            });
    }
}
