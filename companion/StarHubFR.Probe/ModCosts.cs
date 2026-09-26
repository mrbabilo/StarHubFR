using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Reflection;
using System.Reflection.Emit;
using HarmonyLib;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// Ce que chaque mod coûte dans les événements SMAPI : temps **propre** et
/// octets alloués, par mod et par événement, sans seuil (v0.3).
///
/// Point d'accroche : `ManagedEvent&lt;T&gt;.Raise`, qui empile le mod
/// propriétaire de chaque gestionnaire (`Context.HeuristicModsRunningCode.Push`)
/// puis le dépile (`TryPop`). L'idée du transpileur autour de ces deux appels
/// vient de `ManagedEventPatches.cs` du mod Profiler de SinZ (MIT) ; la mise
/// en œuvre est la nôtre : un `dup` passe le mod à `Begin` sans chercher de
/// variable locale, et rien n'est alloué par appel (Profiler crée un
/// chronomètre et une liste à chaque déclenchement).
///
/// Tous les `EventArgs` de SMAPI sont des classes : le code générique est
/// partagé entre elles, et un seul patch couvre tous les événements — mise à
/// jour **et** dessin (`Rendering`, `RenderedWorld`…).
///
/// Mémoire : `GC.GetAllocatedBytesForCurrentThread` compte ce que le
/// gestionnaire alloue — la pression qui déclenche les GC, donc les à-coups.
/// Ce n'est pas la mémoire que le mod **retient**.
/// </summary>
internal static class ModCosts
{
    private static IMonitor Monitor = null!;

    private const int MaxDepth = 64;
    private static readonly int[] StackSlot = new int[MaxDepth];
    private static readonly long[] StackStart = new long[MaxDepth];
    private static readonly long[] StackAlloc = new long[MaxDepth];
    private static readonly long[] StackChildTicks = new long[MaxDepth];
    private static readonly long[] StackChildAlloc = new long[MaxDepth];
    private static int Depth;
    /// <summary>
    /// La pile de mesure est statique : un événement déclenché depuis un autre
    /// fil (chargement de contenu en arrière-plan) la corromprait. Seul le fil
    /// du jeu est mesuré.
    /// </summary>
    private static int MainThreadId;

    /// <summary>Un emplacement par couple (mod, événement), créé à la première rencontre.</summary>
    private static readonly Dictionary<(object Mod, object Event), int> Slots =
        new(new PairComparer());
    private static readonly List<string> SlotMod = new();
    private static readonly List<string> SlotEvent = new();
    /// <summary>Vrai pour un emplacement de patch Harmony (D4-T5), faux pour un événement.</summary>
    private static readonly List<bool> SlotIsPatch = new();
    private static long[] Ticks = new long[256];
    private static long[] Alloc = new long[256];
    private static int[] Calls = new int[256];
    private static long[] MaxTicks = new long[256];
    private static int[] CumulativeCalls = new int[256];

    public static bool Active { get; private set; }

    internal static bool OnMainThread => Environment.CurrentManagedThreadId == MainThreadId;

    public static void Initialize(Harmony harmony, IMonitor monitor)
    {
        Monitor = monitor;
        MainThreadId = Environment.CurrentManagedThreadId;
        try
        {
            Type? open = AccessTools.TypeByName("StardewModdingAPI.Framework.Events.ManagedEvent`1");
            if (open is null)
            {
                monitor.Log("Coût par mod indisponible : ManagedEvent introuvable dans SMAPI.", LogLevel.Warn);
                return;
            }
            // Une instanciation suffit : le code est partagé entre types référence.
            Type closed = open.MakeGenericType(typeof(StardewModdingAPI.Events.UpdateTickedEventArgs));
            int patched = 0;
            foreach (MethodInfo raise in closed.GetMethods(BindingFlags.Instance | BindingFlags.Public))
            {
                if (raise.Name != "Raise") continue;
                harmony.Patch(raise, transpiler: new HarmonyMethod(typeof(ModCosts), nameof(Transpiler)));
                patched++;
            }
            Active = patched > 0;
            monitor.Log($"Coût par mod : {patched} méthode(s) Raise instrumentée(s).", LogLevel.Trace);
        }
        catch (Exception ex)
        {
            monitor.Log($"Coût par mod indisponible : {ex.Message}", LogLevel.Warn);
        }
    }

    private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions)
    {
        MethodInfo begin = AccessTools.Method(typeof(ModCosts), nameof(Begin));
        MethodInfo end = AccessTools.Method(typeof(ModCosts), nameof(End));
        int pushes = 0, pops = 0;
        foreach (CodeInstruction instruction in instructions)
        {
            bool isPush = instruction.operand is MethodInfo { Name: "Push" } m1
                          && m1.DeclaringType?.Name.StartsWith("Stack") == true;
            bool isPop = instruction.operand is MethodInfo { Name: "TryPop" } m2
                         && m2.DeclaringType?.Name.StartsWith("Stack") == true;
            if (isPush)
            {
                // Pile : [pile, mod] → [pile, mod, mod, this] → Begin consomme les deux derniers.
                yield return new CodeInstruction(OpCodes.Dup);
                yield return new CodeInstruction(OpCodes.Ldarg_0);
                yield return new CodeInstruction(OpCodes.Call, begin);
                pushes++;
            }
            yield return instruction;
            if (isPop)
            {
                // TryPop laisse un bool sur la pile ; End n'y touche pas.
                yield return new CodeInstruction(OpCodes.Call, end);
                pops++;
            }
        }
        if (pushes == 0 || pops == 0)
            Monitor.Log($"Raise sans Push/TryPop reconnus ({pushes}/{pops}) : coût par mod partiel.", LogLevel.Warn);
    }

    /// <summary>
    /// Appelé **avant** le `try` de `Raise` : une exception ici sortirait de
    /// SMAPI et priverait les gestionnaires suivants de l'événement. Rien ne
    /// doit lever, et la profondeur ne bouge qu'une fois l'emplacement obtenu.
    /// </summary>
    public static void Begin(object mod, object managedEvent)
    {
        try
        {
            if (Unbalanced || Environment.CurrentManagedThreadId != MainThreadId) return;
            if (Depth >= MaxDepth) { Depth++; return; }
            PushCore(SlotFor(mod, managedEvent));
        }
        catch
        {
            Unbalanced = true;
        }
    }

    private static void PushCore(int slot)
    {
        int d = Depth++;
        StackSlot[d] = slot;
        StackChildTicks[d] = 0;
        StackChildAlloc[d] = 0;
        StackAlloc[d] = GC.GetAllocatedBytesForCurrentThread();
        StackStart[d] = Stopwatch.GetTimestamp();
    }

    /// <summary>
    /// Entrée d'une méthode de patch Harmony (D4-T5). Même pile que les
    /// événements : un patch tiré pendant un gestionnaire sort du temps propre
    /// de ce gestionnaire, et inversement. Fil du jeu seulement, vérifié par
    /// l'appelant.
    /// </summary>
    public static void PushPatch(int slot)
    {
        if (Unbalanced) return;
        try
        {
            if (Depth >= MaxDepth) { Depth++; return; }
            PushCore(slot);
        }
        catch
        {
            Unbalanced = true;
        }
    }

    /// <summary>
    /// Sortie d'une méthode de patch, appelée depuis un finalizer : elle passe
    /// aussi quand le patch lève. Le sommet de la pile doit être ce patch —
    /// sinon la mesure s'arrête plutôt que d'attribuer du temps au mauvais mod.
    /// </summary>
    public static void PopPatch(int slot)
    {
        if (Unbalanced) return;
        try
        {
            if (Depth == 0 || (Depth <= MaxDepth && StackSlot[Depth - 1] != slot))
            {
                Unbalanced = true;
                return;
            }
            EndCore();
        }
        catch
        {
            Unbalanced = true;
        }
    }

    /// <summary>Un emplacement par méthode de patch, créé sur le fil du jeu au moment de l'enveloppe.</summary>
    public static int RegisterPatchSlot(string mod, string label) => AddSlot(mod, label, isPatch: true);

    /// <summary>Appels depuis l'enveloppe, jamais remis à zéro : révèle les patches posés mais jamais appelés.</summary>
    public static int TotalCalls(int slot) => slot < CumulativeCalls.Length ? CumulativeCalls[slot] : 0;

    /// <summary>
    /// Un `Begin` qui a échoué n'a pas empilé : le `End` correspondant ne doit
    /// rien dépiler. Plutôt que de deviner lequel, la mesure s'arrête.
    /// </summary>
    private static bool Unbalanced;

    /// <summary>Pour une enveloppe qui a échoué hors de la pile : la mesure s'arrête.</summary>
    public static void Abandon() => Unbalanced = true;

    public static void End()
    {
        if (Unbalanced || Environment.CurrentManagedThreadId != MainThreadId) return;
        try
        {
            EndCore();
        }
        catch
        {
            Unbalanced = true;
        }
    }

    private static void EndCore()
    {
        long now = Stopwatch.GetTimestamp();
        long allocNow = GC.GetAllocatedBytesForCurrentThread();
        if (Depth == 0) return;
        int d = --Depth;
        if (d >= MaxDepth) return;
        long total = now - StackStart[d];
        long totalAlloc = allocNow - StackAlloc[d];
        long self = Math.Max(0, total - StackChildTicks[d]);
        long selfAlloc = Math.Max(0, totalAlloc - StackChildAlloc[d]);
        int slot = StackSlot[d];
        Ticks[slot] += self;
        Alloc[slot] += selfAlloc;
        Calls[slot]++;
        CumulativeCalls[slot]++;
        if (self > MaxTicks[slot]) MaxTicks[slot] = self;
        if (d > 0)
        {
            StackChildTicks[d - 1] += total;
            StackChildAlloc[d - 1] += totalAlloc;
        }
    }

    private static int SlotFor(object mod, object managedEvent)
    {
        if (Slots.TryGetValue((mod, managedEvent), out int slot)) return slot;
        // Chaque événement est un type générique fermé distinct : la propriété
        // se résout sur le type reçu, jamais sur un type mis en cache.
        string id = (mod.GetType().GetProperty("Manifest")?.GetValue(mod) as IManifest)?.UniqueID
                    ?? mod.ToString() ?? "?";
        string name = managedEvent.GetType().GetProperty("EventName")?.GetValue(managedEvent) as string ?? "?";
        slot = AddSlot(id, name, isPatch: false);
        Slots[(mod, managedEvent)] = slot;
        return slot;
    }

    private static int AddSlot(string mod, string label, bool isPatch)
    {
        int slot = SlotMod.Count;
        SlotMod.Add(mod);
        SlotEvent.Add(label);
        SlotIsPatch.Add(isPatch);
        if (slot >= Ticks.Length)
        {
            int size = Math.Max(Ticks.Length * 2, slot + 1);
            Array.Resize(ref Ticks, size);
            Array.Resize(ref Alloc, size);
            Array.Resize(ref Calls, size);
            Array.Resize(ref MaxTicks, size);
            Array.Resize(ref CumulativeCalls, size);
        }
        return slot;
    }

    /// <summary>`PatchMs` : la part de `SelfMs` passée dans les patches Harmony du mod (D4-T5, opt-in).</summary>
    public record ModCost(string Mod, double SelfMs, double PatchMs, double MsPerSecond, double MaxMs, long AllocKB, int Calls,
                          List<EventCost> Events);
    public record EventCost(string Event, double SelfMs, double MaxMs, long AllocKB, int Calls);

    /// <summary>Le relevé de la fenêtre, trié par temps propre, puis remise à zéro.</summary>
    public static List<ModCost> Drain(double wallSeconds)
    {
        if (Unbalanced) Monitor.Log("Coût par mod interrompu : une mesure a échoué, les chiffres s'arrêtent là.", LogLevel.Warn);
        double msPerTick = 1000.0 / Stopwatch.Frequency;
        var byMod = new Dictionary<string, List<int>>();
        for (int i = 0; i < SlotMod.Count; i++)
        {
            if (Calls[i] == 0) continue;
            if (!byMod.TryGetValue(SlotMod[i], out var list)) byMod[SlotMod[i]] = list = new List<int>();
            list.Add(i);
        }
        var result = new List<ModCost>();
        foreach (var (mod, slots) in byMod)
        {
            long ticks = 0, patchTicks = 0, alloc = 0, max = 0;
            int calls = 0;
            var events = new List<EventCost>();
            foreach (int i in slots)
            {
                ticks += Ticks[i]; alloc += Alloc[i]; calls += Calls[i];
                if (SlotIsPatch[i]) patchTicks += Ticks[i];
                if (MaxTicks[i] > max) max = MaxTicks[i];
                events.Add(new EventCost(SlotEvent[i], Math.Round(Ticks[i] * msPerTick, 2),
                    Math.Round(MaxTicks[i] * msPerTick, 2), Alloc[i] / 1024, Calls[i]));
            }
            events.Sort((a, b) => b.SelfMs.CompareTo(a.SelfMs));
            double selfMs = ticks * msPerTick;
            result.Add(new ModCost(mod, Math.Round(selfMs, 2), Math.Round(patchTicks * msPerTick, 2), Math.Round(selfMs / Math.Max(wallSeconds, 0.001), 3),
                Math.Round(max * msPerTick, 2), alloc / 1024, calls, events));
        }
        result.Sort((a, b) => b.SelfMs.CompareTo(a.SelfMs));
        Array.Clear(Ticks); Array.Clear(Alloc); Array.Clear(Calls); Array.Clear(MaxTicks);
        return result;
    }

    private sealed class PairComparer : IEqualityComparer<(object Mod, object Event)>
    {
        public bool Equals((object Mod, object Event) a, (object Mod, object Event) b) =>
            ReferenceEquals(a.Mod, b.Mod) && ReferenceEquals(a.Event, b.Event);
        public int GetHashCode((object Mod, object Event) p) =>
            HashCode.Combine(System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(p.Mod),
                             System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(p.Event));
    }
}
