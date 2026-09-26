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
///  - mod-costs.jsonl    une ligne par minute : temps et allocations par mod
///  - gmcm-options.json  les options déclarées à GMCM, bornes comprises
///  - patch-wraps.json   (option MeasureHarmonyPatches) ce que la mesure des
///                       patches couvre et ne couvre pas
///  - disjoncteur.txt    (même option) pourquoi les enveloppes ont été retirées
/// </summary>
public sealed class ModEntry : Mod
{
    internal static string OutputDir = "";

    public override void Entry(IModHelper helper)
    {
        OutputDir = Path.Combine(Constants.DataPath, "ModData", ModManifest.UniqueID);
        Directory.CreateDirectory(OutputDir);
        // La cause d'arrêt décrit une session : celle d'avant ne doit pas passer pour celle-ci.
        File.Delete(Path.Combine(OutputDir, "interruption.txt"));
        File.Delete(Path.Combine(OutputDir, "disjoncteur.txt"));

        var config = helper.ReadConfig<ModConfig>();
        var harmony = new Harmony(ModManifest.UniqueID);
        FrameTimings.Initialize(harmony, Monitor);
        ModCosts.Initialize(harmony, Monitor);
        GcPauses.Start(Monitor);
        if (config.MeasureHarmonyPatches)
        {
            PatchCosts.Initialize(helper, Monitor, ModManifest.UniqueID);
            helper.Events.GameLoop.UpdateTicked += (_, _) => PatchBreaker.Poll();
            helper.Events.GameLoop.DayEnding += (_, _) => PatchBreaker.CalmMoment();
            helper.Events.GameLoop.ReturnedToTitle += (_, _) => PatchBreaker.CalmMoment();
        }

        // La carte se relève deux fois : après l'Entry de tous les mods, puis
        // au chargement de la sauvegarde — certains mods patchent tard (modules
        // activés à la demande, intégrations posées quand l'autre mod répond).
        helper.Events.GameLoop.GameLaunched += (_, _) =>
        {
            FrameTimings.LoadedMods = helper.ModRegistry.GetAll().Count();
            HarmonyMap.Write(helper, Monitor, "GameLaunched");
            PatchCosts.WrapNew("GameLaunched");
        };
        helper.Events.GameLoop.SaveLoaded += (_, _) =>
        {
            HarmonyMap.Write(helper, Monitor, "SaveLoaded");
            PatchCosts.WrapNew("SaveLoaded");
            // Les mods s'inscrivent à GMCM pendant GameLaunched : au
            // chargement de la sauvegarde, le registre est complet.
            GmcmExport.Write(helper, Monitor);
        };

        // Plus rien à taper : la minute entamée s'écrit au retour à l'écran
        // titre et à la fermeture du jeu ; la carte se relève chaque matin,
        // pour les patches posés après le chargement (DLX.Bundles, 2026-09-26).
        helper.Events.GameLoop.ReturnedToTitle += (_, _) => FrameTimings.FlushNow();
        helper.Events.GameLoop.DayStarted += (_, _) =>
        {
            HarmonyMap.Write(helper, Monitor, "DayStarted");
            PatchCosts.WrapNew("DayStarted");
        };
        AppDomain.CurrentDomain.ProcessExit += (_, _) => FrameTimings.FlushNow();

        // Facultatif : forcer l'écriture sans attendre la minute.
        helper.ConsoleCommands.Add("starhubfr_probe",
            "Écrit la carte Harmony et la minute de mesures en cours.",
            (_, _) =>
            {
                Monitor.Log(FrameTimings.Status(), LogLevel.Info);
                HarmonyMap.Write(helper, Monitor, "Console");
                GmcmExport.Write(helper, Monitor);
                FrameTimings.FlushNow();
            });
    }
}
