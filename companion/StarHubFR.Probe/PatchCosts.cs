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
    /// <summary>Assembly → UniqueID : un identifiant Harmony n'est pas toujours celui du mod (18 cas sur le parc).</summary>
    private static Dictionary<Assembly, string> ModOfAssembly = new();
    private static double? BiasNsPerCall;

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
    /// `IModInfo` n'expose pas l'instance du mod ; son type réel (`ModMetadata`)
    /// la porte dans `Mod`. Lu par réflexion, une fois, après l'Entry de tous.
    /// </summary>
    private static void MapAssemblies()
    {
        var map = new Dictionary<Assembly, string>();
        foreach (IModInfo info in Helper.ModRegistry.GetAll())
        {
            if (info.GetType().GetProperty("Mod")?.GetValue(info) is IMod mod)
                map.TryAdd(mod.GetType().Assembly, info.Manifest.UniqueID);
        }
        ModOfAssembly = map;
    }

    private static string ModOf(Patch p) =>
        Helper.ModRegistry.Get(p.owner)?.Manifest.UniqueID
        ?? (p.PatchMethod.DeclaringType is { } t && ModOfAssembly.TryGetValue(t.Assembly, out string? id) ? id : null)
        ?? p.owner;

    private static void CalibrationTarget() { }

    /// <summary>
    /// Ce que l'enveloppe ajoute au temps **mesuré** d'un appel : le finalizer
    /// cherche l'emplacement avant que le chronomètre s'arrête. Sur une méthode
    /// vide, tout le temps mesuré est ce biais — `Calls × BiasNsPerCall` se
    /// soustrait à la lecture (D4-T2), décisif pour les patches qui tirent des
    /// milliers de fois par trame.
    /// </summary>
    private static void Calibrate()
    {
        try
        {
            MethodInfo target = AccessTools.Method(typeof(PatchCosts), nameof(CalibrationTarget));
            int slot = ModCosts.RegisterPatchSlot(ProbeId, "calibration");
            SlotOf[target.MethodHandle.Value] = slot;
            Wrapper.Patch(target,
                prefix: new HarmonyMethod(typeof(PatchCosts), nameof(Prefix)),
                finalizer: new HarmonyMethod(typeof(PatchCosts), nameof(Finalizer)));
            var action = (Action)Delegate.CreateDelegate(typeof(Action), target);
            const int n = 100_000;
            for (int i = 0; i < n; i++) action();
            var (ticks, calls) = ModCosts.TakeSlot(slot);
            if (calls == n) BiasNsPerCall = Math.Round(ticks * 1e9 / Stopwatch.Frequency / n, 1);
            Monitor.Log($"Biais de l'enveloppe : {BiasNsPerCall?.ToString() ?? "?"} ns par appel ({calls}/{n} vus).", LogLevel.Info);
        }
        catch (Exception ex)
        {
            Monitor.Log($"Calibration de l'enveloppe impossible : {ex.Message}", LogLevel.Warn);
        }
    }

    /// <summary>
    /// Enveloppe les méthodes de patch pas encore vues. Rappelé à chaque étape
    /// (GameLaunched, SaveLoaded, DayStarted) : certains mods patchent tard.
    /// </summary>
    public static void WrapNew(string stage)
    {
        if (!Active) return;
        if (Stages.Count == 0)
        {
            MapAssemblies();
            Calibrate();
        }
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
                        // Même forme que `Patch` dans harmony-map.json : les deux fichiers se joignent.
                        string label = $"Harmony:{kind} {method.DeclaringType?.FullName}.{method.Name}";
                        if (method.ContainsGenericParameters || method.DeclaringType?.ContainsGenericParameters == true)
                        {
                            Failures.Add($"{p.owner} {label} : méthode générique");
                            continue;
                        }
                        IntPtr key = IntPtr.Zero;
                        try
                        {
                            key = method.MethodHandle.Value;
                            // L'emplacement existe avant le patch : le premier appel le trouve.
                            string mod = ModOf(p);
                            int slot = ModCosts.RegisterPatchSlot(mod, label);
                            SlotOf[key] = slot;
                            Wrapper.Patch(method, prefix: prefix, finalizer: finalizer);
                            Wrapped.Add((mod, label, slot));
                        }
                        catch (Exception ex)
                        {
                            if (key != IntPtr.Zero) SlotOf.Remove(key);
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

    private record Report(string WrittenAt, List<string> Stages, double? BiasNsPerCall, int Wrapped, long OffThreadCalls,
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
            var report = new Report(DateTimeOffset.Now.ToString("o"), Stages, BiasNsPerCall, Wrapped.Count,
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
