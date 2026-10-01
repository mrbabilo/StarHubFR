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
    private object health = new { PackSeam = "missing", AssetHook = "missing", LoadHook = "missing", OffThreadSections = 0, EntryHook = (string?)null, ModLoadHook = (string?)null };

    public LoadRecordBuilder(LoadKind kind, string session, string at, string probeVersion,
                             string? saveName, long? saveBytes, bool reload, bool patchesMeasured)
    {
        this.kind = kind; this.session = session; this.at = at; this.probeVersion = probeVersion;
        this.saveName = saveName; this.saveBytes = saveBytes; this.reload = reload;
        this.patchesMeasured = patchesMeasured;
    }

    public LoadKind Kind => kind;

    /// <summary>Benchmark automatique : identifiant du lancement sous plan, sinon null.</summary>
    public string? BenchmarkRun { get; set; }

    /// <summary>Lancement : durée de la boucle de démarrage des mods (`StartupTimeline.LoopMs`), sinon null.</summary>
    public double? EntryLoopMs { get; set; }
    /// <summary>Lancement : début du premier chargement vu → fin du dernier (`StartupTimeline.LoadLoopMs`).</summary>
    public double? LoadLoopMs { get; set; }
    /// <summary>Chargements réussis vus par la sonde (ceux d'après elle).</summary>
    public int? LoadCoveredMods { get; set; }
    /// <summary>Mods et packs du registre de SMAPI, sonde comprise.</summary>
    public int? LoadTotalMods { get; set; }
    /// <summary>La sonde est la première du registre (`ModsToLoadEarly`) : la boucle de chargement est vue en entier.</summary>
    public bool? ProbeLoadsFirst { get; set; }

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

    /// <summary>`entryHook` null : producteur qui ne connaît pas l'accroche du démarrage (sans avis, jamais « missing »).</summary>
    public void SetHealth(string packSeam, string assetHook, string loadHook, int offThreadSections,
                          string? entryHook = null, string? modLoadHook = null) =>
        health = new { PackSeam = packSeam, AssetHook = assetHook, LoadHook = loadHook,
                       OffThreadSections = offThreadSections, EntryHook = entryHook, ModLoadHook = modLoadHook };

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
        BenchmarkRun,
        EntryLoopMs = EntryLoopMs is { } loop ? Math.Round(loop, 1) : (double?)null,
        LoadLoopMs = LoadLoopMs is { } loadLoop ? Math.Round(loadLoop, 1) : (double?)null,
        LoadCoveredMods,
        LoadTotalMods,
        ProbeLoadsFirst,
    });
}
