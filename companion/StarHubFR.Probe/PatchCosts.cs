using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using HarmonyLib;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// D4-T5 (opt-in) : le coût des **méthodes de patch** Harmony des autres mods
/// — prefix, postfix, finalizer — par mod propriétaire. Un mod qui agit par
/// patch (Stardropium, UltraSmooth, SpaceCore…) échappe à la mesure des
/// événements ; c'est le gros des deux tiers de mise à jour restés invisibles
/// en v0.3.
///
/// Chaque méthode de patch reçoit à son tour un prefix et un **finalizer** de
/// la sonde : le finalizer passe même quand le patch lève, la pile de
/// <see cref="ModCosts"/> reste équilibrée. Pile partagée avec les
/// événements : un patch tiré pendant un gestionnaire sort du temps propre de
/// ce gestionnaire — la somme événements + patches ne compte rien deux fois.
///
/// Angles morts, écrits dans `patch-wraps.json` plutôt que tus : les
/// transpileurs (leur code est fondu dans la méthode d'origine), les méthodes
/// de patch génériques, et celles que le JIT aurait intégrées dans la méthode
/// de remplacement avant l'enveloppe (« jamais appelées »).
/// </summary>
internal static class PatchCosts
{
    /// <summary>Identifiant séparé : la carte Harmony ignore nos enveloppes.</summary>
    public const string WrapperId = "mrbabilo.StarHubFR.Probe.PatchCosts";

    private static IMonitor Monitor = null!;
    private static IModHelper Helper = null!;
    private static Harmony Wrapper = null!;
    private static string ProbeId = "";

    /// <summary>
    /// Écrit et lu sur le fil du jeu seulement : l'appel hors fil sort avant d'y
    /// toucher. Clé : le handle de la méthode, pas l'objet `MethodInfo` — celui
    /// que Harmony passe en `__originalMethod` peut différer par son type réfléchi.
    /// </summary>
    private static readonly Dictionary<IntPtr, int> SlotOf = new();
    private static readonly HashSet<MethodBase> Seen = new();
    private static readonly List<string> Failures = new();
    private static readonly Dictionary<string, int> TranspilersByOwner = new();
    private static readonly List<(string Mod, string Label, int Slot)> Wrapped = new();
    private static readonly List<string> Stages = new();
    private static long OffThreadCalls;

    public static bool Active { get; private set; }

    public static void Initialize(IModHelper helper, IMonitor monitor, string probeId)
    {
        Helper = helper;
        Monitor = monitor;
        ProbeId = probeId;
        Wrapper = new Harmony(WrapperId);
        Active = ModCosts.Active;
        if (!Active)
            monitor.Log("Coût des patches indisponible : la pile du coût par mod n'est pas active.", LogLevel.Warn);
    }

    /// <summary>
    /// Enveloppe les méthodes de patch pas encore vues. Rappelé à chaque étape
    /// (GameLaunched, SaveLoaded, DayStarted) : certains mods patchent tard.
    /// </summary>
    public static void WrapNew(string stage)
    {
        if (!Active) return;
        var watch = Stopwatch.StartNew();
        int wrappedBefore = Wrapped.Count, failedBefore = Failures.Count;
        var prefix = new HarmonyMethod(typeof(PatchCosts), nameof(Prefix)) { priority = Priority.First };
        var finalizer = new HarmonyMethod(typeof(PatchCosts), nameof(Finalizer)) { priority = Priority.Last };
        try
        {
            foreach (MethodBase target in Harmony.GetAllPatchedMethods().ToList())
            {
                Patches? info = Harmony.GetPatchInfo(target);
                if (info is null) continue;
                foreach (Patch p in info.Transpilers)
                {
                    if (!IsOurs(p.owner) && Seen.Add(p.PatchMethod))
                        TranspilersByOwner[p.owner] = TranspilersByOwner.GetValueOrDefault(p.owner) + 1;
                }
                foreach (var (kind, list) in new[] { ("prefix", info.Prefixes), ("postfix", info.Postfixes), ("finalizer", info.Finalizers) })
                {
                    foreach (Patch p in list)
                    {
                        MethodInfo method = p.PatchMethod;
                        if (IsOurs(p.owner) || !Seen.Add(method)) continue;
                        string label = $"Harmony:{kind} {method.DeclaringType?.Name}.{method.Name}";
                        if (method.ContainsGenericParameters || method.DeclaringType?.ContainsGenericParameters == true)
                        {
                            Failures.Add($"{p.owner} {label} : méthode générique");
                            continue;
                        }
                        try
                        {
                            // L'emplacement existe avant le patch : le premier appel le trouve.
                            string mod = Helper.ModRegistry.Get(p.owner)?.Manifest.UniqueID ?? p.owner;
                            int slot = ModCosts.RegisterPatchSlot(mod, label);
                            SlotOf[method.MethodHandle.Value] = slot;
                            Wrapper.Patch(method, prefix: prefix, finalizer: finalizer);
                            Wrapped.Add((mod, label, slot));
                        }
                        catch (Exception ex)
                        {
                            SlotOf.Remove(method.MethodHandle.Value);
                            Failures.Add($"{p.owner} {label} : {ex.GetType().Name} {ex.Message}");
                        }
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Monitor.Log($"Coût des patches ({stage}) interrompu : {ex}", LogLevel.Warn);
        }
        watch.Stop();
        Stages.Add($"{stage} : +{Wrapped.Count - wrappedBefore} enveloppés, +{Failures.Count - failedBefore} échecs, {watch.ElapsedMilliseconds} ms");
        Monitor.Log($"Coût des patches ({stage}) : {Wrapped.Count - wrappedBefore} méthodes enveloppées en {watch.ElapsedMilliseconds} ms, "
                    + $"{Failures.Count - failedBefore} échecs.", LogLevel.Info);
        WriteReport();
    }

    private static bool IsOurs(string owner) => owner == ProbeId || owner == WrapperId;

    /// <summary>
    /// Enveloppe posée dans le code d'un autre mod : rien ne doit en sortir.
    /// Un échec ici arrête la mesure (<see cref="ModCosts"/>), jamais le patch.
    /// </summary>
    private static void Prefix(MethodBase __originalMethod)
    {
        try
        {
            if (!ModCosts.OnMainThread)
            {
                System.Threading.Interlocked.Increment(ref OffThreadCalls);
                return;
            }
            if (SlotOf.TryGetValue(__originalMethod.MethodHandle.Value, out int slot)) ModCosts.PushPatch(slot);
        }
        catch
        {
            ModCosts.Abandon();
        }
    }

    private static void Finalizer(MethodBase __originalMethod)
    {
        try
        {
            if (!ModCosts.OnMainThread) return;
            if (SlotOf.TryGetValue(__originalMethod.MethodHandle.Value, out int slot)) ModCosts.PopPatch(slot);
        }
        catch
        {
            ModCosts.Abandon();
        }
    }

    private record Report(string WrittenAt, List<string> Stages, int Wrapped, long OffThreadCalls,
                          int NeverCalledCount, Dictionary<string, List<string>> NeverCalledByMod,
                          Dictionary<string, int> TranspilersByOwner, List<string> Failures);

    /// <summary>
    /// `patch-wraps.json`, réécrit à chaque étape et à chaque minute écrite :
    /// les « jamais appelées » ne se lisent qu'après un temps de jeu.
    /// </summary>
    public static void WriteReport()
    {
        if (!Active) return;
        try
        {
            var never = Wrapped.Where(w => ModCosts.TotalCalls(w.Slot) == 0)
                .GroupBy(w => w.Mod)
                .OrderBy(g => g.Key, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(g => g.Key, g => g.Select(w => w.Label).ToList());
            var report = new Report(DateTimeOffset.Now.ToString("o"), Stages, Wrapped.Count,
                System.Threading.Interlocked.Read(ref OffThreadCalls),
                never.Values.Sum(l => l.Count), never,
                TranspilersByOwner.OrderBy(kv => kv.Key, StringComparer.OrdinalIgnoreCase)
                    .ToDictionary(kv => kv.Key, kv => kv.Value),
                Failures);
            File.WriteAllText(Path.Combine(ModEntry.OutputDir, "patch-wraps.json"),
                JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex)
        {
            Monitor.Log($"patch-wraps.json non écrit : {ex.Message}", LogLevel.Trace);
        }
    }
}
