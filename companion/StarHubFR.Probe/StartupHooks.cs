using System;
using System.Collections.Generic;
using System.Diagnostics;
using HarmonyLib;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// Démarrage des mods (spec 2026-10-01 § 3) : posé dans le **constructeur**
/// de <see cref="ModEntry"/>, pendant la boucle de chargement de SMAPI —
/// donc avant toute la boucle de démarrage, quelle que soit la position de
/// la sonde. Deux postfix, une fois chacun :
///  - `SCore.ReloadTranslations(IEnumerable&lt;IModMetadata&gt;)` : départ ;
///  - `ModMetadata.SetApi` : fin de `Entry` + `GetApi` de chaque mod.
/// Validés par la porte du 2026-10-01 (SMAPI 4.5.2 : 1 et 140 appels). Un
/// postfix ne lève jamais : `SetApi` est dans le `try` de SMAPI.
/// </summary>
internal static class StartupHooks
{
    public static readonly StartupTimeline Timeline = new(Stopwatch.Frequency);
    public static string? ArmError { get; private set; }
    private static bool patched;

    public static string HealthNow => patched && Timeline.Recorded > 0 ? "ok" : "missing";

    public static void Arm()
    {
        try
        {
            var harmony = new Harmony("mrbabilo.StarHubFR.Probe.startup");
            Type? score = AccessTools.TypeByName("StardewModdingAPI.Framework.SCore");
            Type? metaInterface = AccessTools.TypeByName("StardewModdingAPI.Framework.IModMetadata");
            Type? meta = AccessTools.TypeByName("StardewModdingAPI.Framework.ModLoading.ModMetadata");
            var reload = score is null || metaInterface is null ? null
                : AccessTools.Method(score, "ReloadTranslations",
                    new[] { typeof(IEnumerable<>).MakeGenericType(metaInterface) });
            var setApi = meta is null ? null : AccessTools.Method(meta, "SetApi");
            if (reload is null || setApi is null)
            {
                ArmError = $"accroche introuvable (ReloadTranslations={reload is not null}, SetApi={setApi is not null})";
                return;
            }
            harmony.Patch(reload, postfix: new HarmonyMethod(typeof(StartupHooks), nameof(AfterReload)));
            harmony.Patch(setApi, postfix: new HarmonyMethod(typeof(StartupHooks), nameof(AfterSetApi)));
            patched = true;
        }
        catch (Exception ex)
        {
            ArmError = $"{ex.GetType().Name} : {ex.Message}";
        }
    }

    private static void AfterReload()
    {
        try { Timeline.LoopStarted(Stopwatch.GetTimestamp(), ModCosts.AttributedTicks); }
        catch { /* jamais dans la boucle de SMAPI */ }
    }

    private static void AfterSetApi(object __instance)
    {
        try
        {
            string? id = __instance is IModInfo info ? info.Manifest?.UniqueID : null;
            Timeline.EntryEnded(id, Stopwatch.GetTimestamp(), ModCosts.AttributedTicks);
        }
        catch { /* jamais dans le try de SMAPI */ }
    }
}
