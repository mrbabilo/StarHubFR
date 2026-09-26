using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
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
/// enveloppe son corps dans `Enter(emplacement)` … `finally { Exit(); }` : la
/// sortie passe même quand le patch lève, la pile de
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

    // Témoins de l'autotest : plusieurs `ret`, valeur de retour, boucle,
    // try/catch interne qui rend depuis le catch, exception qui traverse.
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static int WitnessReturns(int x)
    {
        if (x < 0) return -1;
        for (int i = 0; i < 3; i++)
            if (x == i) return i * 10;
        try
        {
            if (x == 50) throw new ArgumentException("témoin");
        }
        catch (ArgumentException)
        {
            return 5;
        }
        return x + 1;
    }

    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static string WitnessThrows(bool fail) => fail ? throw new InvalidOperationException("témoin") : "ok";

    private static int WitnessCounter;

    /// <summary>Void, corps qui commence par un `try`, `leave` internes qui visent le `ret` final.</summary>
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static void WitnessVoidTry(int x)
    {
        try
        {
            if (x == 1) throw new ArgumentException("témoin");
            WitnessCounter += 1;
        }
        catch (ArgumentException)
        {
            WitnessCounter += 100;
        }
    }

    /// <summary>Boucle `do … while` en tête : saut arrière sur la première instruction.</summary>
    [System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
    private static int WitnessLoop(int n)
    {
        do
        {
            n -= 3;
        } while (n > 0);
        return n;
    }

    /// <summary>
    /// Le transpileur réécrit le corps des patches des autres mods : un IL
    /// faux y lèverait à chaque appel, en jeu. Avant d'envelopper quoi que ce
    /// soit, il est éprouvé sur les témoins de la sonde — mêmes résultats,
    /// entrées et sorties appariées, pile intacte. Au moindre écart, rien
    /// d'autre n'est enveloppé.
    /// </summary>
    private static bool SelfTest()
    {
        try
        {
            int[] inputs = { -3, 0, 1, 2, 7, 50 };
            int[] loops = { 7, -2 };
            int Run()
            {
                WitnessCounter = 0;
                WitnessVoidTry(0);
                WitnessVoidTry(1);
                return WitnessCounter;
            }
            int[] expected = inputs.Select(WitnessReturns).Concat(loops.Select(WitnessLoop)).Append(Run()).ToArray();

            int slot = ModCosts.RegisterPatchSlot(ProbeId, "autotest");
            foreach (string name in new[] { nameof(WitnessReturns), nameof(WitnessThrows), nameof(WitnessVoidTry), nameof(WitnessLoop) })
            {
                MethodInfo witness = AccessTools.Method(typeof(PatchCosts), name);
                SlotOf[witness.MethodHandle.Value] = slot;
                Wrapper.Patch(witness, transpiler: Transpiler);
            }

            int[] actual = inputs.Select(WitnessReturns).Concat(loops.Select(WitnessLoop)).Append(Run()).ToArray();
            bool thrown = false;
            try { WitnessThrows(true); } catch (InvalidOperationException) { thrown = true; }
            string ok = WitnessThrows(false);
            var (_, _, calls) = ModCosts.TakeSlot(slot);
            int expectedCalls = inputs.Length + loops.Length + 2 + 2;

            bool pass = actual.SequenceEqual(expected) && thrown && ok == "ok"
                        && calls == expectedCalls && !ModCosts.Interrupted;
            Monitor.Log(pass
                    ? $"Autotest de l'enveloppe : {calls}/{expectedCalls} appels, résultats identiques."
                    : $"Autotest de l'enveloppe échoué (résultats {string.Join(",", actual)} pour {string.Join(",", expected)}, "
                      + $"exception {thrown}, appels {calls}/{expectedCalls}, interrompu {ModCosts.Interrupted}) : "
                      + "aucun patch ne sera enveloppé.",
                pass ? LogLevel.Info : LogLevel.Warn);
            return pass;
        }
        catch (Exception ex)
        {
            Monitor.Log($"Autotest de l'enveloppe impossible ({ex.GetType().Name} : {ex.Message}) : aucun patch ne sera enveloppé.", LogLevel.Warn);
            return false;
        }
    }

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
            Wrapper.Patch(target, transpiler: Transpiler);
            for (int i = 0; i < n; i++) action();
            ModCosts.TakeSlot(slot);
            long wrapped = Stopwatch.GetTimestamp();
            for (int i = 0; i < n; i++) action();
            wrapped = Stopwatch.GetTimestamp() - wrapped;

            var (ticks, alloc, calls) = ModCosts.TakeSlot(slot);
            double nsPerTick = 1e9 / Stopwatch.Frequency;
            if (calls != n)
            {
                Active = false;
                Monitor.Log($"Calibration : {calls}/{n} appels vus — aucun patch ne sera enveloppé.", LogLevel.Warn);
            }
            else
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
            Active = false;
            Monitor.Log($"Calibration de l'enveloppe impossible ({ex.Message}) : aucun patch ne sera enveloppé.", LogLevel.Warn);
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
            Active = SelfTest();
            if (Active) Calibrate();
            if (!Active)
            {
                Stages.Add($"{stage} : enveloppe désactivée (autotest ou calibration)");
                WriteReport();
                return;
            }
            PatchBreaker.Arm(Monitor);
        }
        PatchBreaker.StageReached(stage);
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
                            Wrapper.Patch(method, transpiler: Transpiler);
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

    /// <summary>
    /// Retire toutes les enveloppes (<see cref="PatchBreaker"/>), sur le fil du
    /// jeu. Un cadre déjà entré garde l'ancien code, donc son `finally` : la
    /// pile reste appariée, et la mesure des événements continue.
    /// </summary>
    public static string Disarm(string reason)
    {
        Active = false;
        string outcome;
        try
        {
            Wrapper.UnpatchAll(WrapperId);
            outcome = $"{Wrapped.Count} enveloppes retirées";
        }
        catch (Exception ex)
        {
            outcome = $"retrait impossible ({ex.GetType().Name} : {ex.Message}), relancer le jeu sans l'option";
        }
        Stages.Add($"disjoncteur : {reason} — {outcome}");
        WriteReport();
        return outcome;
    }

    private static bool IsOurs(string owner) => owner == ProbeId || owner == WrapperId;

    private static readonly HarmonyMethod Transpiler =
        new(typeof(PatchCosts), nameof(InjectEnterExit)) { priority = Priority.Last };

    /// <summary>
    /// Enveloppe le **corps** de la méthode de patch :
    /// `Enter(emplacement); try { corps } finally { Exit(); }`, l'emplacement
    /// en constante. Entrée et sortie vivent dans le corps : si un autre mod
    /// patche cette méthode de patch et en saute le corps (Stardropium sur le
    /// postfix `CharacterPatch.UpdatePostfix` d'AlternativeTextures, session
    /// v0.4.4), les deux sont sautés ensemble. La v0.4.3 sortait par un
    /// finalizer Harmony, qui passe même corps sauté : pile vide, mesure
    /// arrêtée au chargement de la sauvegarde.
    ///
    /// Chaque `ret` devient `stloc résultat; leave fin` (un `ret` n'existe
    /// qu'hors des blocs protégés, `leave` y est donc toujours valide) ; les
    /// préfixes `tail.` sautent, interdits dans un `try`. Les étiquettes
    /// restent sur la première instruction d'origine : une boucle qui y
    /// revient ne ré-empile pas.
    /// </summary>
    private static IEnumerable<CodeInstruction> InjectEnterExit(IEnumerable<CodeInstruction> instructions,
        ILGenerator generator, MethodBase original)
    {
        List<CodeInstruction> body = instructions.ToList();
        if (!SlotOf.TryGetValue(original.MethodHandle.Value, out int slot) || body.Count == 0)
        {
            ModCosts.Abandon($"transpileur : aucun emplacement pour {original.DeclaringType?.FullName}.{original.Name}");
            return body;
        }
        Type returnType = (original as MethodInfo)?.ReturnType ?? typeof(void);
        LocalBuilder? result = returnType == typeof(void) ? null : generator.DeclareLocal(returnType);
        Label done = generator.DefineLabel();

        var output = new List<CodeInstruction>(body.Count + 8)
        {
            new(OpCodes.Ldc_I4, slot),
            new(OpCodes.Call, AccessTools.Method(typeof(PatchCosts), nameof(Enter))),
        };
        body[0].blocks.Insert(0, new ExceptionBlock(ExceptionBlockType.BeginExceptionBlock));
        List<Label> pendingLabels = new();
        List<ExceptionBlock> pendingBlocks = new();
        foreach (CodeInstruction instruction in body)
        {
            if (instruction.opcode == OpCodes.Tailcall)
            {
                // Ses étiquettes et blocs passent à l'instruction suivante.
                pendingLabels.AddRange(instruction.labels);
                pendingBlocks.AddRange(instruction.blocks);
                continue;
            }
            if (pendingLabels.Count > 0 || pendingBlocks.Count > 0)
            {
                instruction.labels.InsertRange(0, pendingLabels);
                instruction.blocks.InsertRange(0, pendingBlocks);
                pendingLabels.Clear();
                pendingBlocks.Clear();
            }
            if (instruction.opcode == OpCodes.Ret)
            {
                if (result is not null)
                {
                    var store = new CodeInstruction(OpCodes.Stloc, result);
                    instruction.MoveLabelsTo(store);
                    instruction.MoveBlocksTo(store);
                    output.Add(store);
                    output.Add(new CodeInstruction(OpCodes.Leave, done));
                }
                else
                {
                    output.Add(new CodeInstruction(OpCodes.Leave, done).WithLabels(instruction.labels).WithBlocks(instruction.blocks));
                }
                continue;
            }
            output.Add(instruction);
        }
        // La sortie connaît aussi son emplacement : le sommet de pile doit être
        // ce patch-là, pas seulement un patch.
        var exitSlot = new CodeInstruction(OpCodes.Ldc_I4, slot);
        exitSlot.blocks.Add(new ExceptionBlock(ExceptionBlockType.BeginFinallyBlock));
        output.Add(exitSlot);
        var exit = new CodeInstruction(OpCodes.Call, AccessTools.Method(typeof(PatchCosts), nameof(Exit)));
        exit.blocks.Add(new ExceptionBlock(ExceptionBlockType.EndExceptionBlock));
        output.Add(exit);
        var tail = result is not null ? new CodeInstruction(OpCodes.Ldloc, result) : new CodeInstruction(OpCodes.Nop);
        tail.labels.Add(done);
        output.Add(tail);
        output.Add(new CodeInstruction(OpCodes.Ret));
        return output;
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

    public static void Exit(int slot)
    {
        try
        {
            if (ModCosts.OnMainThread) ModCosts.PopPatch(slot);
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
        // Désactivée par l'autotest : le rapport le dit quand même.
        if (Stages.Count == 0) return;
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
