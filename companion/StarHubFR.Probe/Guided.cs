using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using StardewModdingAPI;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>
/// D5-A — la mesure guidée. L'app écrit `guided-plan.json` et est **seule à
/// l'effacer** ; la sonde applique `GuidedRule` à chaque minute écrite dans
/// `timings.jsonl` et écrit la mesure close dans `guided-measurements.jsonl`.
/// </summary>
internal static class Guided
{
    internal sealed record Plan(int Version, string Id, string Name, string Role, string? Location,
                                string? PairedWith, string? CreatedAt);
    private sealed record ExcludedLine(string At, string Reason);
    private sealed record Line(int Version, string PlanId, string Name, string Role, string? PairedWith,
        string Session, string Location, string? Start, string? End, IReadOnlyList<string> KeptAt,
        IReadOnlyList<ExcludedLine> Excluded, string Outcome, double? FrameIqrShare, double? WorkIqrShare,
        int? GameTimeFrom, int? GameTimeTo, string Probe);

    private static IMonitor? Monitor;
    private static string ProbeVersion = "";
    private static string PlanPath => Path.Combine(ModEntry.OutputDir, "guided-plan.json");
    private static string OutputPath => Path.Combine(ModEntry.OutputDir, "guided-measurements.jsonl");

    private static readonly ComparableGuards Guards = new();
    private static readonly HashSet<string> Finished = new();
    private static DateTime planStamp;
    private static int targetTicks;
    private static bool patchesSeen;
    /// <summary>Posé par le relevé d'inventaire, qui tourne en tâche de fond.</summary>
    private static int configChanged;

    internal static Plan? Active { get; private set; }
    internal static GuidedRule? Rule { get; private set; }
    internal static MinuteReason? LastReason { get; private set; }
    internal static DateTime? FinishedAtUtc { get; private set; }
    internal static string? RefusedKey { get; private set; }
    internal static int StateVersion { get; private set; }
    /// <summary>La fenêtre du jeu a le focus : sans lui, rien ne se dessine et les minutes sont écartées.</summary>
    internal static bool WindowActive { get; private set; } = true;

    public static void Initialize(IMonitor monitor, string probeVersion)
    {
        Monitor = monitor;
        ProbeVersion = probeVersion;
    }

    /// <summary>À l'`Entry`, avant d'armer la mesure des patches (spec : un plan en attente la désarme).</summary>
    public static bool PlanPending() => ReadPlan(log: false) is not null;

    /// <summary>Appelé par l'inventaire quand il écrit une ligne `configChanged`.</summary>
    public static void NoteConfigChanged() => Interlocked.Exchange(ref configChanged, 1);

    /// <summary>À chaque tick (postfix de `Game.Tick`), fil du jeu.</summary>
    public static void OnTick(bool windowActive)
    {
        WindowActive = windowActive;
        if (PatchCosts.Active) patchesSeen = true;
        if (Rule is { Outcome: GuidedOutcome.Running } rule && Context.IsWorldReady && !Game1.eventUp
            && Game1.currentLocation?.NameOrUniqueName == rule.Target)
            targetTicks++;
    }

    /// <summary>
    /// À chaque fermeture de fenêtre de `FrameTimings`. `written` : la minute
    /// si sa ligne a bien été écrite, `null` sinon — elle n'avance alors rien.
    /// </summary>
    public static void CloseWindow(MinuteFacts? written)
    {
        int ticks = targetTicks;
        bool patches = patchesSeen;
        targetTicks = 0;
        patchesSeen = false;
        if (written is MinuteFacts facts)
        {
            // Les gardes communes courent sur toute la session, plan ou pas.
            var guard = Guards.Classify(facts);
            bool changed = Interlocked.Exchange(ref configChanged, 0) == 1;
            if (Rule is { Outcome: GuidedOutcome.Running } rule)
            {
                if (RefusedKey is not null) { /* refusé (écran partagé) : aucune minute ne compte */ }
                else if (!FrameTimings.TicksCounted) Refuse("refused.noticks");
                else
                {
                    LastReason = rule.Add(facts with { TargetTicks = ticks, PatchesActive = patches, ConfigChanged = changed }, guard);
                    if (rule.Outcome != GuidedOutcome.Running) Finish(rule);
                }
                StateVersion++;
            }
        }
        RefreshPlan();
    }

    /// <summary>Au chargement de la sauvegarde, puis à chaque minute.</summary>
    public static void RefreshPlan()
    {
        try
        {
            if (!File.Exists(PlanPath))
            {
                // Effacé par l'app : « Abandonner », ou mesure close relue. Arrêt sans ligne ;
                // une mesure finie garde son bandeau de fin.
                if (Rule?.Outcome == GuidedOutcome.Running || RefusedKey is not null) Stop();
                planStamp = default;
                return;
            }
            DateTime stamp = File.GetLastWriteTimeUtc(PlanPath);
            if (stamp == planStamp) return;
            planStamp = stamp;
            var plan = ReadPlan(log: true);
            if (plan is null || plan.Id == Active?.Id) return;
            if (Rule?.Outcome == GuidedOutcome.Running) Abandon(keepStamp: true);   // plan remplacé
            Start(plan);
        }
        catch (Exception ex)
        {
            Log($"Plan de mesure non lu : {ex.Message}");
        }
    }

    /// <summary>Retour à l'écran titre : la mesure en cours est abandonnée, le plan reste.</summary>
    public static void Abandon() => Abandon(keepStamp: false);

    /// <summary>
    /// Fermeture du jeu : **en premier** dans `ProcessExit`, sans aucun journal
    /// (SMAPI a déjà fermé le sien).
    /// </summary>
    public static void AbandonAtExit()
    {
        try
        {
            if (Rule is { Outcome: GuidedOutcome.Running } rule && rule.KeptAt.Count > 0) WriteLine("abandoned");
        }
        catch (Exception) { }
    }

    // MARK: — Privé

    private static void Abandon(bool keepStamp)
    {
        try
        {
            if (Rule is { Outcome: GuidedOutcome.Running } rule && rule.KeptAt.Count > 0) WriteLine("abandoned");
        }
        catch (Exception ex) { Log($"Mesure abandonnée non écrite : {ex.Message}"); }
        Stop();
        // Relire le même plan à la prochaine partie : il repart de zéro.
        if (!keepStamp) planStamp = default;
    }

    private static void Start(Plan plan)
    {
        Active = plan;
        Rule = new GuidedRule(plan.Location!);
        LastReason = null;
        FinishedAtUtc = null;
        RefusedKey = null;
        targetTicks = 0;
        patchesSeen = false;
        Interlocked.Exchange(ref configChanged, 0);
        if (Context.IsSplitScreen) Refuse("refused.splitscreen");
        StateVersion++;
        Log($"Mesure guidée « {plan.Name} » prête ({plan.Location}).");
    }

    private static void Refuse(string key)
    {
        if (RefusedKey == key) return;
        RefusedKey = key;
        Log($"Mesure guidée refusée : {key}.");
    }

    private static void Stop()
    {
        Active = null;
        Rule = null;
        LastReason = null;
        RefusedKey = null;
        StateVersion++;
    }

    private static void Finish(GuidedRule rule)
    {
        string outcome = rule.Outcome == GuidedOutcome.Stable ? "stable" : "noisy";
        try { WriteLine(outcome); }
        catch (Exception ex) { Log($"Mesure guidée non écrite : {ex.Message}"); }
        if (Active is not null) Finished.Add(Active.Id);
        FinishedAtUtc = DateTime.UtcNow;
        Log($"Mesure guidée « {Active?.Name} » terminée : {outcome}, {rule.KeptAt.Count} min.");
    }

    private static void WriteLine(string outcome)
    {
        if (Active is not { } plan || Rule is not { } rule) return;
        var kept = rule.KeptAt;
        var line = new Line(1, plan.Id, plan.Name, plan.Role, plan.PairedWith, FrameTimings.Session, rule.Target,
            kept.FirstOrDefault(), kept.LastOrDefault(), kept,
            rule.Excluded.Select(e => new ExcludedLine(e.At, GuidedRule.ReasonName(e.Reason))).ToList(),
            outcome, Round(rule.FrameIqrShare), Round(rule.WorkIqrShare),
            rule.GameTimeFrom, rule.GameTimeTo, ProbeVersion);
        File.AppendAllText(OutputPath, JsonSerializer.Serialize(line) + "\n");
    }

    private static double? Round(double? value) => value is double v ? Math.Round(v, 4) : null;

    private static Plan? ReadPlan(bool log)
    {
        if (!File.Exists(PlanPath)) return null;
        Plan? plan;
        try { plan = JsonSerializer.Deserialize<Plan>(File.ReadAllText(PlanPath)); }
        catch (Exception ex)
        {
            if (log) Log($"Plan de mesure illisible, ignoré : {ex.Message}");
            return null;
        }
        if (plan is null || plan.Version != 1 || string.IsNullOrWhiteSpace(plan.Id)
            || string.IsNullOrWhiteSpace(plan.Location))
        {
            if (log) Log("Plan de mesure incomplet ou de version inconnue, ignoré.");
            return null;
        }
        // Déjà close : l'app ne l'a pas encore relue ni effacée.
        if (Finished.Contains(plan.Id) || IsFinishedOnDisk(plan.Id)) return null;
        return plan;
    }

    private static bool IsFinishedOnDisk(string id)
    {
        if (!File.Exists(OutputPath)) return false;
        foreach (string text in File.ReadLines(OutputPath))
        {
            try
            {
                using var doc = JsonDocument.Parse(text);
                var root = doc.RootElement;
                if (root.GetProperty("PlanId").GetString() == id
                    && root.GetProperty("Outcome").GetString() is "stable" or "noisy")
                    return true;
            }
            catch (Exception) { /* ligne coupée : ignorée, comme côté app */ }
        }
        return false;
    }

    private static void Log(string message)
    {
        try { Monitor?.Log(message, LogLevel.Info); }
        catch (ObjectDisposedException) { }
    }
}
