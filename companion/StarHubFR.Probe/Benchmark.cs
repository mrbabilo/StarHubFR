using System;
using System.IO;
using StardewModdingAPI;
using StardewModdingAPI.Events;
using StardewValley;
using StardewValley.Menus;

namespace StarHubFR.Probe;

/// <summary>
/// Benchmark automatique (spec 2026-09-30 §4). Sous plan valide : charge la
/// sauvegarde du plan 5 s après L4 — le geste exact de
/// `LoadGameMenu.SaveFileSlot.Activate` (`SaveGame.Load` puis
/// `Game1.exitActiveMenu`) —, écrit la ligne de chargement 5 s après S9, puis
/// pose `Game1.quit`. Le jeu ne passe jamais la première journée : aucun
/// enregistrement de partie. La sonde n'efface jamais le plan.
/// </summary>
internal static class Benchmark
{
    private static IMonitor Monitor = null!;
    private static BenchmarkPlanData? Plan;
    private static double? L4At, S9At;
    private static bool Loaded, Quitting;

    private static string PlanPath => Path.Combine(ModEntry.OutputDir, "benchmark-plan.json");

    public static bool Pending => Plan is not null;
    public static string? RunId => Plan?.RunId;

    public static void Initialize(IModHelper helper, IMonitor monitor)
    {
        Monitor = monitor;
        string? json = null;
        try { if (File.Exists(PlanPath)) json = File.ReadAllText(PlanPath); }
        catch (Exception ex) { monitor.Log($"Benchmark : plan illisible ({ex.Message}).", LogLevel.Trace); }
        Plan = BenchmarkRule.Parse(json, DateTimeOffset.Now);
        if (json is not null && Plan is null)
            monitor.Log("Benchmark : plan ignoré (illisible, expiré ou d'une autre version).", LogLevel.Info);
        if (Plan is null) return;
        monitor.Log($"Benchmark : lancement {Plan.RunId}, sauvegarde {Plan.SaveName}.", LogLevel.Info);
        helper.Events.GameLoop.UpdateTicking += OnUpdateTicking;
        helper.Events.GameLoop.UpdateTicked += OnUpdateTicked;
    }

    public static void MarkL4(double ms) => L4At ??= ms;
    public static void MarkS9(double ms) => S9At ??= ms;

    /// <summary>
    /// `Game1._update` s'arrête avant `if (quit) Exit()` et avant l'avance du
    /// chargement quand la fenêtre est inactive et `pauseWhenOutOfFocus` vrai
    /// (défaut) : une série sans présence se figerait dès que le jeu passe en
    /// arrière-plan. Réaffirmé à chaque tick — `SaveGame` remplace
    /// `Game1.options` par celles de la sauvegarde en plein chargement. Rien
    /// n'est persisté : le chargement écrit `default_options` depuis les
    /// options de la sauvegarde **avant** tout tick suivant, et une affectation
    /// directe ne marque pas `optionsDirty` (1.6.15 décompilé le 2026-09-30).
    /// </summary>
    private static void OnUpdateTicking(object? sender, UpdateTickingEventArgs e)
    {
        if (Game1.options is { } options) options.pauseWhenOutOfFocus = false;
    }

    [EventPriority((EventPriority)int.MinValue + 1)]
    private static void OnUpdateTicked(object? sender, UpdateTickedEventArgs e)
    {
        if (Plan is null || Quitting) return;
        double now = Loads.Now;
        if (BenchmarkRule.ShouldLoad(L4At, now, Game1.activeClickableMenu is TitleMenu, Loaded))
        {
            Loaded = true;
            if (!AutoLoad.Try(Plan.SaveName, Monitor, "Benchmark")) Quit();
            return;
        }
        if (BenchmarkRule.ShouldQuit(S9At, now))
        {
            Loads.FlushNow();
            Quit();
        }
    }

    private static void Quit()
    {
        Quitting = true;
        Monitor.Log("Benchmark : fin du lancement, fermeture du jeu.", LogLevel.Info);
        Game1.quit = true;
    }
}
