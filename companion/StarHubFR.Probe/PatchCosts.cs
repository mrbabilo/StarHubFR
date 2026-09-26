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
/// Chaque méthode de patch reçoit à son tour un transpileur de la sonde, qui
/// pose en tête `Enter(emplacement)` avec l'emplacement en constante, et un
/// **finalizer** : le finalizer passe même quand le patch lève, la pile de
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
    private static double? BiasBytesPerCall;
    private static double? OverheadNsPerCall;

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

    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static void CalibrationTarget() { }

    /// <summary>
    /// Deux chiffres sur une méthode vide, 100 000 appels :
    /// - le **biais** : ce que l'enveloppe laisse dans le temps et les octets
    ///   **mesurés** (entre les deux lectures d'horloge) — `Calls × biais` se
    ///   soustrait à la lecture (D4-T2) ;
    /// - le **surcoût complet** par appel, enveloppé moins nu : multiplié par
    ///   les appels d'une minute, c'est ce que la sonde coûte au jeu.
    /// La v0.4.2 passait `__originalMethod` : 87 octets alloués par appel,
    /// 2,8 Go par minute sur le parc, FPS divisés par trois (session du
    /// 2026-09-26). D'où le transpileur à constante.
    /// </summary>
    private static void Calibrate()
    {
        try
        {
            MethodInfo target = AccessTools.Method(typeof(PatchCosts), nameof(CalibrationTarget));
            var action = (Action)Delegate.CreateDelegate(typeof(Action), target);
            const int n = 100_000;
            for (int i = 0; i < n; i++) action();
            long bare = Stopwatch.GetTimestamp();
            for (int i = 0; i < n; i++) action();
            bare = Stopwatch.GetTimestamp() - bare;

            int slot = ModCosts.RegisterPatchSlot(ProbeId, "calibration");
            SlotOf[target.MethodHandle.Value] = slot;
            Wrapper.Patch(target, transpiler: Transpiler, finalizer: Finalizer);
            for (int i = 0; i < n; i++) action();
            ModCosts.TakeSlot(slot);
            long wrapped = Stopwatch.GetTimestamp();
            for (int i = 0; i < n; i++) action();
            wrapped = Stopwatch.GetTimestamp() - wrapped;

            var (ticks, alloc, calls) = ModCosts.TakeSlot(slot);
            double nsPerTick = 1e9 / Stopwatch.Frequency;
            if (calls == n)
            {
                BiasNsPerCall = Math.Round(ticks * nsPerTick / n, 1);
                BiasBytesPerCall = Math.Round((double)alloc / n, 1);
                OverheadNsPerCall = Math.Round((wrapped - bare) * nsPerTick / n, 1);
            }
            Monitor.Log($"Enveloppe : biais {BiasNsPerCall?.ToString() ?? "?"} ns et {BiasBytesPerCall?.ToString() ?? "?"} octets "
                        + $"par appel, surcoût complet {OverheadNsPerCall?.ToString() ?? "?"} ns ({calls}/{n} vus).", LogLevel.Info);
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
                            Wrapper.Patch(method, transpiler: Transpiler, finalizer: Finalizer);
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

    private static readonly HarmonyMethod Transpiler =
        new(typeof(PatchCosts), nameof(InjectEnter)) { priority = Priority.Last };
    private static readonly HarmonyMethod Finalizer =
        new(typeof(PatchCosts), nameof(Exit)) { priority = Priority.Last };

    /// <summary>
    /// `Enter(emplacement)` en tête du corps de la méthode de patch,
    /// l'emplacement résolu ici une fois pour toutes. Les étiquettes restent
    /// sur la première instruction d'origine : une boucle qui y revient ne
    /// ré-empile pas. Emplacement introuvable : aucune injection, et la
    /// mesure s'arrête plutôt que de dépiler le mauvais cadre au finalizer.
    /// </summary>
    private static IEnumerable<CodeInstruction> InjectEnter(IEnumerable<CodeInstruction> instructions, MethodBase original)
    {
        if (SlotOf.TryGetValue(original.MethodHandle.Value, out int slot))
        {
            yield return new CodeInstruction(System.Reflection.Emit.OpCodes.Ldc_I4, slot);
            yield return new CodeInstruction(System.Reflection.Emit.OpCodes.Call,
                AccessTools.Method(typeof(PatchCosts), nameof(Enter)));
        }
        else
        {
            ModCosts.Abandon($"transpileur : aucun emplacement pour {original.DeclaringType?.FullName}.{original.Name}");
        }
        foreach (CodeInstruction instruction in instructions) yield return instruction;
    }

    /// <summary>
    /// Enveloppe posée dans le code d'un autre mod : rien ne doit en sortir.
    /// Un échec ici arrête la mesure (<see cref="ModCosts"/>), jamais le patch.
    /// </summary>
    public static void Enter(int slot)
    {
        try
        {
            if (!ModCosts.OnMainThread)
            {
                System.Threading.Interlocked.Increment(ref OffThreadCalls);
                return;
            }
            ModCosts.PushPatch(slot);
        }
        catch (Exception ex)
        {
            ModCosts.Abandon($"enveloppe : {ex.GetType().Name} {ex.Message}");
        }
    }

    private static void Exit()
    {
        try
        {
            if (ModCosts.OnMainThread) ModCosts.PopPatchTop();
        }
        catch (Exception ex)
        {
            ModCosts.Abandon($"enveloppe : {ex.GetType().Name} {ex.Message}");
        }
    }

    private record Report(string WrittenAt, List<string> Stages, double? BiasNsPerCall, double? BiasBytesPerCall,
                          double? OverheadNsPerCall, int Wrapped, long OffThreadCalls,
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
            var report = new Report(DateTimeOffset.Now.ToString("o"), Stages, BiasNsPerCall, BiasBytesPerCall,
                OverheadNsPerCall, Wrapped.Count,
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
