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
///  - inventory.jsonl    mods chargés (version, empreinte du config.json) au
///                       lancement, puis chaque réglage changé en partie
///  - configs/           le contenu de chaque config.json, par empreinte
///  - mod-costs.jsonl    une ligne par minute : temps et allocations par mod
///  - gmcm-options.json  les options déclarées à GMCM, bornes comprises
///  - patch-wraps.json   (option MeasureHarmonyPatches) ce que la mesure des
///                       patches couvre et ne couvre pas
///  - disjoncteur.txt    (même option) pourquoi les enveloppes ont été retirées
///  - loads.jsonl        (D5-B) une ligne par lancement et par chargement de
///                       sauvegarde : jalons, coût par mod et par pack
///  - guided-measurements.jsonl  (D5-A) une ligne par mesure guidée close ;
///                       le plan, guided-plan.json, est écrit et effacé par l'app
/// </summary>
public sealed class ModEntry : Mod
{
    internal static string OutputDir = "";

    /// <summary>
    /// SMAPI crée l'instance pendant sa boucle de chargement, avant toute la
    /// boucle de démarrage : seul endroit d'où le démarrage de **tous** les
    /// mods se voit. `Monitor` n'existe pas encore — l'échec se journalise à `Entry`.
    /// </summary>
    public ModEntry() => StartupHooks.Arm();

    public override void Entry(IModHelper helper)
    {
        OutputDir = Path.Combine(Constants.DataPath, "ModData", ModManifest.UniqueID);
        Directory.CreateDirectory(OutputDir);
        // La cause d'arrêt décrit une session : celle d'avant ne doit pas passer pour celle-ci.
        File.Delete(Path.Combine(OutputDir, "interruption.txt"));
        File.Delete(Path.Combine(OutputDir, "disjoncteur.txt"));

        var config = helper.ReadConfig<ModConfig>();
        var harmony = new Harmony(ModManifest.UniqueID);
        if (StartupHooks.ArmError is { } armError)
            Monitor.Log($"Démarrage des mods non mesuré : {armError}.", LogLevel.Trace);
        FrameTimings.Initialize(harmony, Monitor);
        ModCosts.Initialize(harmony, Monitor);
        GcPauses.Start(Monitor);
        Guided.Initialize(Monitor, ModManifest.Version.ToString());
        // Démarrer le plan **tout de suite** : l'auto-chargement de la
        // sauvegarde choisie se déclenche à l'écran titre, où `RefreshPlan`
        // n'était appelé qu'au `SaveLoaded` — trop tard d'un chargement.
        Guided.RefreshPlan();
        GuidedBanner.Initialize(helper);
        // Avant Loads.Initialize : l'enregistrement de lancement lit Benchmark.RunId.
        Benchmark.Initialize(helper, Monitor);
        // D5-A : un plan en attente désarme la mesure des patches pour la
        // session — le disjoncteur la coupe 5 min après le chargement, et une
        // mesure à cheval mélangerait deux états que l'app refuse de comparer.
        bool guidedPending = Guided.PlanPending();
        bool benchmarkPending = Benchmark.Pending;
        if (config.MeasureHarmonyPatches && guidedPending)
            Monitor.Log("Mesure guidée en attente : la mesure des patches n'est pas armée pour cette session.", LogLevel.Info);
        // Benchmark : la mesure des patches pèserait différemment d'un côté à
        // l'autre (parc contre profil minimal) — désarmée sous plan.
        if (config.MeasureHarmonyPatches && benchmarkPending)
            Monitor.Log("Benchmark : la mesure des patches n'est pas armée pour cette session.", LogLevel.Info);
        if (config.MeasureHarmonyPatches && !guidedPending && !benchmarkPending)
        {
            PatchCosts.Initialize(helper, Monitor, ModManifest.UniqueID);
            helper.Events.GameLoop.UpdateTicked += (_, _) => PatchBreaker.Poll();
            helper.Events.GameLoop.DayEnding += (_, _) => PatchBreaker.CalmMoment();
            helper.Events.GameLoop.ReturnedToTitle += (_, _) => PatchBreaker.CalmMoment();
        }

        // D5-B : après le bloc ci-dessus — l'enregistrement de lancement lit
        // `PatchCosts.Active`, qui vient d'être fixé.
        ContentPackSections.Initialize(helper, harmony, Monitor);
        Loads.Initialize(helper, harmony, Monitor, ModManifest.Version.ToString(), ModManifest.UniqueID);
        // D4-T6a : opt-in, par événements — la mesure des patches peut rester armée à côté.
        TextureMemory.Initialize(helper, Monitor, config.MeasureTextures);
        // D4-T6 bis : les options réglables en jeu (GMCM facultatif).
        ConfigMenu.Initialize(helper, Monitor, config, ModManifest);

        // La carte se relève deux fois : après l'Entry de tous les mods, puis
        // au chargement de la sauvegarde — certains mods patchent tard (modules
        // activés à la demande, intégrations posées quand l'autre mod répond).
        helper.Events.GameLoop.GameLaunched += (_, _) =>
        {
            FrameTimings.LoadedMods = helper.ModRegistry.GetAll().Count();
            Inventory.WriteLaunch(helper, Monitor, ModManifest.Version.ToString());
            HarmonyMap.Write(helper, Monitor, "GameLaunched");
            PatchCosts.WrapNew("GameLaunched");
        };
        helper.Events.GameLoop.SaveLoaded += (_, _) =>
        {
            Guided.RefreshPlan();
            HarmonyMap.Write(helper, Monitor, "SaveLoaded");
            PatchCosts.WrapNew("SaveLoaded");
            // Les mods s'inscrivent à GMCM pendant GameLaunched : au
            // chargement de la sauvegarde, le registre est complet.
            GmcmExport.Write(helper, Monitor);
        };

        // Plus rien à taper : la minute entamée s'écrit au retour à l'écran
        // titre et à la fermeture du jeu ; la carte se relève chaque matin,
        // pour les patches posés après le chargement (DLX.Bundles, 2026-09-26).
        helper.Events.GameLoop.ReturnedToTitle += (_, _) =>
        {
            FrameTimings.FlushNow();
            Guided.Abandon();
            Loads.Abandon();
        };
        helper.Events.GameLoop.DayStarted += (_, _) =>
        {
            HarmonyMap.Write(helper, Monitor, "DayStarted");
            PatchCosts.WrapNew("DayStarted");
        };
        // SMAPI ferme son journal dans son propre ProcessExit, appelé avant le
        // nôtre : les fichiers de mesures sont déjà écrits, seul le
        // `Monitor.Log` qui suit lève (« Critical app domain exception »).
        AppDomain.CurrentDomain.ProcessExit += (_, _) =>
        {
            // La ligne guidée d'abord, dans son propre try, sans journal.
            Guided.AbandonAtExit();
            try
            {
                FrameTimings.FlushNow();
                // Dernier relevé, synchrone : un Task.Run ici est tué par la
                // fin du processus (réglages perdus de la dernière minute,
                // 2026-09-28).
                Inventory.FlushSync();
                Loads.AbandonAtExit();
            }
            catch (ObjectDisposedException) { }
        };

        // Facultatif : forcer l'écriture sans attendre la minute.
        helper.ConsoleCommands.Add("starhubfr_probe",
            "Écrit la carte Harmony et la minute de mesures en cours.",
            (_, _) =>
            {
                Monitor.Log(FrameTimings.Status(), LogLevel.Info);
                HarmonyMap.Write(helper, Monitor, "Console", force: true);
                GmcmExport.Write(helper, Monitor, force: true);
                FrameTimings.FlushNow();
            });
    }
}
