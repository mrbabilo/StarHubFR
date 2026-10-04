using System;
using System.Collections.Generic;
using System.Linq;

namespace StarHubFR.Probe;

/// <summary>
/// Pourquoi une minute ne compte pas (D5-A). Les cinq premières raisons sont
/// celles de l'app (`ProbeExclusionReason`), dans le même ordre ; les quatre
/// dernières n'existent que pour la mesure guidée.
/// </summary>
public enum MinuteReason
{
    Kept, Unfocused, Title, MenuOpen, Night, FirstAfterTitle,
    PatchesMeasured, Partial, OtherLocation, ConfigChanged,
}

/// <summary>
/// Les chiffres d'une minute écrite dans `timings.jsonl`, plus ce que la sonde
/// a compté pendant : ticks au lieu cible, mesure des patches active, réglage
/// relevé changé.
/// </summary>
public readonly record struct MinuteFacts(
    string At, double WallSeconds, int InactiveTicks, string? Location, int? MenuTicks, int? TickCount,
    int? GameTime, double? FrameP50, double? WorkP50,
    int TargetTicks = 0, bool PatchesActive = false, bool ConfigChanged = false);

/// <summary>
/// Les gardes 1 à 5 : copie de `ProbeComparableMinutes.filter` (app), même
/// ordre. Appliquées à **chaque** minute depuis le lancement, plan ou pas :
/// l'état « en partie » et l'heure précédente courent sur la session entière,
/// comme côté app. Parité vérifiée par `comparable-reasons.json`.
/// </summary>
public sealed class ComparableGuards
{
    private bool previousInGame;
    private int? previousGameTime;

    public MinuteReason Classify(MinuteFacts m)
    {
        MinuteReason reason;
        if (m.InactiveTicks > 0) reason = MinuteReason.Unfocused;
        else if (m.Location is null) reason = MinuteReason.Title;
        else if (m.MenuTicks is int menu && m.TickCount is int ticks && ticks > 0 && (double)menu / ticks >= 0.5)
            reason = MinuteReason.MenuOpen;
        else if (m.GameTime is int time && previousGameTime is int previous && time < previous)
            reason = MinuteReason.Night;
        else if (!previousInGame) reason = MinuteReason.FirstAfterTitle;
        else reason = MinuteReason.Kept;

        // L'état suit le lieu, pas la garde : seul l'écran titre referme.
        if (m.Location is null) { previousInGame = false; previousGameTime = null; }
        else { previousInGame = true; previousGameTime = m.GameTime; }
        return reason;
    }
}

public enum GuidedOutcome { Running, Stable, Noisy }

/// <summary>
/// Une mesure guidée : gardes 6 à 9 après les communes, décompte, arrêt. La
/// stabilité se juge sur le **travail** de trame (update + draw p50) : la
/// trame p50 saute d'un multiple de synchro à l'autre.
/// </summary>
public sealed class GuidedRule
{
    public const int MinimumMinutes = 5;
    public const int MaximumMinutes = 15;
    public const double StableIqrShare = 0.10;
    public const double MinimumWallSeconds = 45;

    private readonly List<(string At, double? Frame, double? Work, int? GameTime)> kept = new();
    private readonly List<(string At, MinuteReason Reason)> excluded = new();

    public GuidedRule(string target) => Target = target;

    public string Target { get; }
    public IReadOnlyList<string> KeptAt => kept.Select(k => k.At).ToList();
    /// <summary>Le compte seul, sans liste : le bandeau le lit à chaque trame.</summary>
    public int KeptCount => kept.Count;
    public IReadOnlyList<(string At, MinuteReason Reason)> Excluded => excluded;
    public GuidedOutcome Outcome { get; private set; } = GuidedOutcome.Running;
    /// <summary>La dernière minute a remis le décompte à zéro (réglage changé).</summary>
    public bool JustReset { get; private set; }
    public double? FrameIqrShare => IqrShare(kept.Where(k => k.Frame.HasValue).Select(k => k.Frame!.Value).ToList());
    public double? WorkIqrShare => IqrShare(kept.Where(k => k.Work.HasValue).Select(k => k.Work!.Value).ToList());
    public int? GameTimeFrom => kept.Min(k => k.GameTime);
    public int? GameTimeTo => kept.Max(k => k.GameTime);

    /// <summary>`guard` : le verdict de `ComparableGuards` pour cette minute.</summary>
    public MinuteReason Add(MinuteFacts m, MinuteReason guard)
    {
        if (Outcome != GuidedOutcome.Running) return guard;
        JustReset = false;
        if (m.ConfigChanged)
        {
            // Coupure de segment côté app : rien d'avant ne se compare à la
            // suite, et la minute courante peut contenir le `ChangedAt`.
            foreach (var k in kept) excluded.Add((k.At, MinuteReason.ConfigChanged));
            kept.Clear();
            excluded.Add((m.At, MinuteReason.ConfigChanged));
            JustReset = true;
            return MinuteReason.ConfigChanged;
        }
        var reason = guard != MinuteReason.Kept ? guard
            : m.PatchesActive ? MinuteReason.PatchesMeasured
            : m.WallSeconds < MinimumWallSeconds ? MinuteReason.Partial
            : m.TickCount is not int ticks || ticks <= 0 || m.TargetTicks * 2 < ticks ? MinuteReason.OtherLocation
            : MinuteReason.Kept;
        if (reason != MinuteReason.Kept)
        {
            excluded.Add((m.At, reason));
            return reason;
        }
        kept.Add((m.At, m.FrameP50, m.WorkP50, m.GameTime));
        if (kept.Count >= MinimumMinutes && WorkIqrShare is double work && work <= StableIqrShare)
            Outcome = GuidedOutcome.Stable;
        else if (kept.Count >= MaximumMinutes)
            Outcome = GuidedOutcome.Noisy;
        return reason;
    }

    /// <summary>IQR / médiane, quartiles de Tukey exactement comme `ProbeStats` (app).</summary>
    public static double? IqrShare(IReadOnlyList<double> values)
    {
        if (values.Count < 2) return null;
        double[] sorted = values.OrderBy(v => v).ToArray();
        int half = (sorted.Length + 1) / 2;
        double median = Median(sorted);
        if (median == 0) return null;
        double q1 = Median(sorted[..half]);
        double q3 = Median(sorted[^half..]);
        return (q3 - q1) / Math.Abs(median);
    }

    private static double Median(double[] sorted)
    {
        int middle = sorted.Length / 2;
        return sorted.Length % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
    }

    /// <summary>Le nom écrit dans `guided-measurements.jsonl` et `comparable-reasons.json`.</summary>
    public static string ReasonName(MinuteReason reason)
    {
        string name = reason.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }
}
