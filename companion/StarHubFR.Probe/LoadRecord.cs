using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace StarHubFR.Probe;

public enum LoadKind { Launch, Save }

/// <summary>
/// Les jalons d'un chargement (D5-B, spec §3), dans l'ordre. `L0` : début du
/// processus ; `S0` : `SaveGame.Load`. `S10` (première trame où le joueur est
/// libre) n'est jamais un jalon de phase : il attend un humain.
/// </summary>
public static class LoadMilestones
{
    public static readonly string[] Launch = { "L0", "L1", "L2", "L3", "L4" };
    public static readonly string[] Save = { "S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9" };
    public const string FinalSave = "S10";
}

public sealed record CostLine(string Mod, string Kind, string Label, double Ms, double AllocMb, int Calls);

/// <summary>
/// Un enregistrement de `loads.jsonl`, construit jalon après jalon. Pur : rien
/// de SMAPI ni de Harmony, pour les tests hors jeu.
/// </summary>
public sealed class LoadRecordBuilder
{
    private readonly LoadKind kind;
    private readonly string session, at, probeVersion;
    private readonly string? saveName;
    private readonly long? saveBytes;
    private readonly bool reload, patchesMeasured;
    private readonly List<(string Name, double Ms)> milestones = new();
    private readonly List<object> phases = new();
    private object? final;
    private string? saveDate;
    private object health = new { PackSeam = "missing", AssetHook = "missing", LoadHook = "missing", OffThreadSections = 0 };

    public LoadRecordBuilder(LoadKind kind, string session, string at, string probeVersion,
                             string? saveName, long? saveBytes, bool reload, bool patchesMeasured)
    {
        this.kind = kind; this.session = session; this.at = at; this.probeVersion = probeVersion;
        this.saveName = saveName; this.saveBytes = saveBytes; this.reload = reload;
        this.patchesMeasured = patchesMeasured;
    }

    public LoadKind Kind => kind;

    /// <summary>Un jalon atteint, avec ce qui a coûté depuis le précédent.</summary>
    public void Mark(string name, double ms, IReadOnlyList<CostLine> costsSincePrevious)
    {
        if (milestones.Count > 0)
        {
            var (from, fromMs) = milestones[^1];
            phases.Add(new { From = from, To = name, Ms = Math.Round(ms - fromMs, 1), Costs = costsSincePrevious });
        }
        milestones.Add((name, ms));
    }

    public void SetFinal(string name, double ms, string? menu) =>
        final = new { Name = name, Ms = Math.Round(ms, 1), Menu = menu };

    public void SetSaveDate(string date) => saveDate = date;

    public void SetHealth(string packSeam, string assetHook, string loadHook, int offThreadSections) =>
        health = new { PackSeam = packSeam, AssetHook = assetHook, LoadHook = loadHook, OffThreadSections = offThreadSections };

    /// <summary>Tous les jalons attendus, dans l'ordre, chacun une fois.</summary>
    public bool Complete =>
        milestones.Select(m => m.Name).SequenceEqual(kind == LoadKind.Launch ? LoadMilestones.Launch : LoadMilestones.Save);

    public string ToJsonLine() => JsonSerializer.Serialize(new
    {
        Kind = kind == LoadKind.Launch ? "launch" : "save",
        Session = session,
        At = at,
        ProbeVersion = probeVersion,
        Complete,
        Reload = reload,
        SaveName = saveName,
        PatchesMeasured = patchesMeasured,
        SaveBytes = saveBytes,
        SaveDate = saveDate,
        Milestones = milestones.Select(m => new { m.Name, Ms = Math.Round(m.Ms, 1) }),
        Phases = phases,
        Final = final,
        Health = health,
    });
}
