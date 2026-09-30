// companion/StarHubFR.Probe/BenchmarkRule.cs
using System;
using System.Text.Json;

namespace StarHubFR.Probe;

/// <summary>`benchmark-plan.json`, écrit et effacé par l'app seule (contrat D5-A).</summary>
public sealed record BenchmarkPlanData(int Version, string RunId, string SaveName, DateTimeOffset ExpiresAt);

/// <summary>
/// Benchmark automatique (spec 2026-09-30 §4) : lecture du plan et décisions
/// « charger maintenant » / « quitter maintenant ». Pur : rien de SMAPI, pour
/// les tests hors jeu. Un plan absent, illisible, d'une autre version ou
/// expiré n'est pas un plan — un lancement manuel n'est jamais détourné.
/// </summary>
public static class BenchmarkRule
{
    public const int SupportedVersion = 1;
    /// <summary>Après L4 : laisser finir le démarrage (caches de mods, écritures de config).</summary>
    public const double LoadDelayMs = 5000;
    /// <summary>Après S9 : le chargement est complet (S10 n'entre pas dans le total).</summary>
    public const double QuitDelayMs = 5000;

    public static BenchmarkPlanData? Parse(string? json, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        BenchmarkPlanData? plan;
        try { plan = JsonSerializer.Deserialize<BenchmarkPlanData>(json); }
        catch (JsonException) { return null; }
        if (plan is null || plan.Version != SupportedVersion) return null;
        if (string.IsNullOrWhiteSpace(plan.RunId) || string.IsNullOrWhiteSpace(plan.SaveName)) return null;
        if (plan.ExpiresAt <= now) return null;
        return plan;
    }

    public static bool ShouldLoad(double? l4AtMs, double nowMs, bool titleMenu, bool alreadyLoaded) =>
        !alreadyLoaded && titleMenu && l4AtMs is { } l4 && nowMs - l4 >= LoadDelayMs;

    public static bool ShouldQuit(double? s9AtMs, double nowMs) =>
        s9AtMs is { } s9 && nowMs - s9 >= QuitDelayMs;
}
