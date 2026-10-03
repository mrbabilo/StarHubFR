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
///
/// L'arithmétique de la pile et les compteurs vivent dans <see cref="CostStack"/>
/// (testée hors jeu) ; ici ne restent que l'accroche Harmony, les
/// emplacements nommés et le relevé par minute.
/// </summary>
internal static class ModCosts
{
    private static IMonitor Monitor = null!;

    private static readonly CostStack Stack = new();
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
    /// <summary>`event` (gestionnaire), `patch`, `asset` (rappel LoadFrom/Edit) ou `pack` (section Content Patcher).</summary>
    private static readonly List<string> SlotKind = new();

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

            // D5-B : les rappels d'assets (LoadFrom/Edit). Pour une méthode
            // **générique**, Harmony ne détourne que le stub `<object>` et les
            // vrais appels passent par le corps partagé — `Raise`, méthode
            // simple d'un type générique, marche. On accroche donc
            // `SCore.RequestAssetOperations`, non générique, qui rend les
            // opérations fraîches de chaque requête (SMAPI 4.5.2 décompilé),
            // et on enveloppe leurs délégués.
            Type? score = AccessTools.TypeByName("StardewModdingAPI.Framework.SCore");
            MethodInfo? request = score is null ? null : AccessTools.Method(score, "RequestAssetOperations");
            Type? group = AccessTools.TypeByName("StardewModdingAPI.Framework.Content.AssetOperationGroup");
            Type? loadOp = AccessTools.TypeByName("StardewModdingAPI.Framework.Content.AssetLoadOperation");
            Type? editOp = AccessTools.TypeByName("StardewModdingAPI.Framework.Content.AssetEditOperation");
            GroupLoads = group?.GetProperty("LoadOperations");
            GroupEdits = group?.GetProperty("EditOperations");
            LoadMod = loadOp?.GetProperty("Mod");
            LoadGetData = loadOp is null ? null : AccessTools.Field(loadOp, "<GetData>k__BackingField");
            EditMod = editOp?.GetProperty("Mod");
            EditApply = editOp is null ? null : AccessTools.Field(editOp, "<ApplyEdit>k__BackingField");
            if (request is not null && GroupLoads is not null && GroupEdits is not null && LoadMod is not null
                && LoadGetData?.FieldType == typeof(Func<IAssetInfo, object>)
                && EditMod is not null && EditApply?.FieldType == typeof(Action<IAssetData>))
            {
                harmony.Patch(request, postfix: new HarmonyMethod(typeof(ModCosts), nameof(WrapAssetOperations)));
                AssetHookPatched = true;
            }
            monitor.Log(AssetHookPatched
                ? "Rappels d'assets : RequestAssetOperations accroché."
                : "Rappels d'assets non mesurés : RequestAssetOperations ou ses opérations introuvables dans SMAPI.",
                AssetHookPatched ? LogLevel.Trace : LogLevel.Warn);
            RefreshAssetHook();
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

    private static bool AssetHookPatched;
    private static PropertyInfo? GroupLoads, GroupEdits, LoadMod, EditMod;
    private static FieldInfo? LoadGetData, EditApply;
    /// <summary>Diagnostic D5-B, cumulé depuis le lancement : opérations enveloppées, rappels vus, rappels hors du fil du jeu.</summary>
    private static int AssetOpsWrapped, AssetBegins, AssetOffThread;
    public static string AssetDiagnostic =>
        $"depuis le lancement, {AssetOpsWrapped} opération(s) d'asset enveloppée(s), {AssetBegins} rappel(s) vu(s) dont {AssetOffThread} hors du fil du jeu";
    public static string AssetHook { get; private set; } = "missing";
    public static int AssetCallsSeen { get; private set; }

    /// <summary>X119 : l'état de l'accroche passe par la règle pure — « missing » ne dit plus « rien vu ».</summary>
    private static void RefreshAssetHook() => AssetHook = ProbeHealth.AssetHook(AssetHookPatched, AssetCallsSeen);

    /// <summary>
    /// Postfix de `SCore.RequestAssetOperations` : chaque `GetData`/`ApplyEdit`
    /// rendu est remplacé par une enveloppe qui mesure le rappel sous son mod.
    /// Les opérations sont neuves à chaque requête (`LoadFrom`/`Edit` les
    /// créent) et SMAPI ne fait qu'invoquer ces délégués : les réécrire en
    /// place ne change rien d'autre. Le `finally` garde la pile équilibrée si
    /// le rappel lève (SMAPI rattrape l'exception plus haut).
    /// </summary>
    private static void WrapAssetOperations(object? __result)
    {
        if (__result is null || Unbalanced) return;
        try
        {
            if (GroupLoads!.GetValue(__result) is System.Collections.IList loads)
                foreach (object op in loads)
                {
                    if (LoadGetData!.GetValue(op) is not Func<IAssetInfo, object> load || LoadMod!.GetValue(op) is not { } mod)
                        continue;
                    LoadGetData.SetValue(op, (Func<IAssetInfo, object>)(info =>
                    {
                        BeginLabeled(mod, "AssetLoad");
                        try { return load(info); }
                        finally { End(); }
                    }));
                    AssetOpsWrapped++;
                }
            if (GroupEdits!.GetValue(__result) is System.Collections.IList edits)
                foreach (object op in edits)
                {
                    if (EditApply!.GetValue(op) is not Action<IAssetData> apply || EditMod!.GetValue(op) is not { } mod)
                        continue;
                    EditApply.SetValue(op, (Action<IAssetData>)(asset =>
                    {
                        BeginLabeled(mod, "AssetEdit");
                        try { apply(asset); }
                        finally { End(); }
                    }));
                    AssetOpsWrapped++;
                }
        }
        catch (Exception ex)
        {
            Fail($"WrapAssetOperations a levé {ex.GetType().Name} : {ex.Message}");
        }
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
            PushCore(SlotFor(mod, managedEvent));
        }
        catch (Exception ex)
        {
            Fail($"Begin a levé {ex.GetType().Name} : {ex.Message}");
        }
    }

    private static readonly Dictionary<(string Pack, string Event), int> SectionSlots = new();

    /// <summary>Rappel d'asset (`GetData`/`ApplyEdit` enveloppé) : même pile, emplacement « phase seulement ».</summary>
    public static void BeginLabeled(object mod, string label)
    {
        try
        {
            AssetBegins++;
            if (Environment.CurrentManagedThreadId != MainThreadId) AssetOffThread++;
            if (Unbalanced || Environment.CurrentManagedThreadId != MainThreadId) return;
            if (!Slots.TryGetValue((mod, label), out int slot))
            {
                slot = AddSlot(ModId(mod), label, isPatch: false, phaseOnly: true, kind: "asset");
                Slots[(mod, label)] = slot;
            }
            PushCore(slot);
        }
        catch (Exception ex)
        {
            Fail($"BeginLabeled a levé {ex.GetType().Name} : {ex.Message}");
        }
    }

    public static int SectionSlot(string packId, string eventType)
    {
        if (SectionSlots.TryGetValue((packId, eventType), out int slot)) return slot;
        slot = AddSlot(packId, eventType, isPatch: false, phaseOnly: true, kind: "pack");
        SectionSlots[(packId, eventType)] = slot;
        return slot;
    }

    /// <summary>Section de pack Content Patcher. Fil du jeu seulement, vérifié par l'appelant.</summary>
    public static void PushSection(int slot) => Push("Section", slot);

    public static void PopSection(int slot) => Pop("section", slot);

    /// <summary>
    /// Entrée d'une section de pack ou d'une méthode de patch Harmony (D4-T5) :
    /// même pile que les événements — ce qui se tire dedans sort du temps
    /// propre du cadre parent, et inversement. Fil du jeu seulement, vérifié
    /// par l'appelant.
    /// </summary>
    public static void PushPatch(int slot) => Push("Patch", slot);

    private static void Push(string what, int slot)
    {
        if (Unbalanced) return;
        try { PushCore(slot); }
        catch (Exception ex) { Fail($"Push{what} a levé {ex.GetType().Name} : {ex.Message}"); }
    }

    /// <summary>
    /// Sortie d'une section ou d'un patch, appelée depuis le `Dispose` ou le
    /// `finally` injecté : elle passe aussi quand le cadre lève. Le sommet doit
    /// être ce cadre — sinon la mesure s'arrête plutôt que d'attribuer du temps
    /// au mauvais mod.
    /// </summary>
    public static void PopPatch(int slot) => Pop("patch", slot);

    private static void Pop(string what, int slot)
    {
        if (Unbalanced) return;
        try
        {
            if (Stack.Depth == 0)
            {
                Fail($"sortie de {what} sur une pile vide");
                return;
            }
            if (Stack.Depth <= CostStack.MaxDepth && Stack.TopSlot != slot)
            {
                Fail($"sortie de {what} {SlotEvent[slot]}, mais le sommet de la pile est un autre cadre");
                return;
            }
            EndCore();
        }
        catch (Exception ex) { Fail($"Pop{what} a levé {ex.GetType().Name} : {ex.Message}"); }
    }

    /// <summary>D5-B : vrai pendant une fenêtre de chargement ; la fermer vide la phase.</summary>
    public static bool PhaseOpen
    {
        get => Stack.PhaseOpen;
        set { Stack.PhaseOpen = value; if (!value) Stack.ClearPhase(); }
    }

    /// <summary>Compteur monotone de <see cref="CostStack.PhaseRootTicks"/> (ticks `Stopwatch`).</summary>
    public static long AttributedTicks => Stack.PhaseRootTicks;

    /// <summary>Ce qui a coûté depuis le jalon précédent, puis remise à zéro de la phase.</summary>
    public static List<CostLine> TakePhase(string selfId)
    {
        double msPerTick = 1000.0 / Stopwatch.Frequency;
        var lines = new List<CostLine>();
        for (int i = 0; i < Stack.SlotCount; i++)
        {
            if (Stack.PhaseCalls[i] == 0) continue;
            if (string.Equals(SlotMod[i], selfId, StringComparison.OrdinalIgnoreCase)) continue;
            lines.Add(new CostLine(SlotMod[i], SlotKind[i], SlotEvent[i],
                Math.Round(Stack.PhaseTicks[i] * msPerTick, 2),
                Math.Round(Stack.PhaseAlloc[i] / 1_048_576.0, 2), Stack.PhaseCalls[i]));
            if (SlotKind[i] == "asset") AssetCallsSeen += Stack.PhaseCalls[i];
        }
        lines.Sort((a, b) => b.Ms.CompareTo(a.Ms));
        Stack.ClearPhase();
        RefreshAssetHook();
        return lines;
    }

    private static void PushCore(int slot) =>
        Stack.Push(slot, Stopwatch.GetTimestamp(), GC.GetAllocatedBytesForCurrentThread());

    /// <summary>
    /// Fil du jeu : un cadre de patch est-il ouvert sur la pile ? Mettre les
    /// enveloppes en veille ou les retirer à ce moment désapparierait sa sortie
    /// (<see cref="PatchBreaker"/>). Pile débordée : on ne sait pas, donc oui.
    /// </summary>
    public static bool PatchOnStack()
    {
        if (Stack.Depth > CostStack.MaxDepth) return true;
        for (int i = 0; i < Stack.Depth; i++)
            if (SlotKind[Stack.SlotAt(i)] == "patch") return true;
        return false;
    }

    /// <summary>Un emplacement par méthode de patch, créé sur le fil du jeu au moment de l'enveloppe.</summary>
    public static int RegisterPatchSlot(string mod, string label) => AddSlot(mod, label, isPatch: true);

    /// <summary>Appels depuis l'enveloppe, jamais remis à zéro : révèle les patches posés mais jamais appelés.</summary>
    public static int TotalCalls(int slot) => slot < Stack.CumulativeCalls.Length ? Stack.CumulativeCalls[slot] : 0;

    /// <summary>
    /// Un `Begin` qui a échoué n'a pas empilé : le `End` correspondant ne doit
    /// rien dépiler. Plutôt que de deviner lequel, la mesure s'arrête.
    /// </summary>
    private static bool Unbalanced;
    private static bool InterruptLogged;

    /// <summary>Pour une enveloppe qui a échoué hors de la pile : la mesure s'arrête.</summary>
    public static void Abandon(string reason) => Fail(reason);

    /// <summary>
    /// La première cause d'arrêt, avec l'état de la pile et la pile d'appels :
    /// sans elle, « une mesure a échoué » ne se diagnostique pas (session
    /// v0.4.3, arrêt pendant le chargement de la sauvegarde). Rien d'alloué
    /// tant que tout va bien.
    /// </summary>
    public static string? InterruptReason { get; private set; }

    private static void Fail(string reason)
    {
        if (Unbalanced) return;
        Unbalanced = true;
        try
        {
            var frames = new System.Text.StringBuilder();
            frames.AppendLine($"Cause : {reason}");
            frames.AppendLine($"Fil {Environment.CurrentManagedThreadId} (jeu : {MainThreadId}), profondeur {Stack.Depth}");
            for (int d = Math.Min(Stack.Depth, CostStack.MaxDepth) - 1, shown = 0; d >= 0 && shown < 8; d--, shown++)
                frames.AppendLine($"  [{d}] {SlotMod[Stack.SlotAt(d)]} — {SlotEvent[Stack.SlotAt(d)]}");
            frames.AppendLine("Pile d'appels :");
            frames.AppendLine(Environment.StackTrace);
            InterruptReason = reason;
            System.IO.File.WriteAllText(System.IO.Path.Combine(ModEntry.OutputDir, "interruption.txt"), frames.ToString());
        }
        catch
        {
            InterruptReason ??= reason;
        }
    }

    /// <summary>Vrai dès qu'une mesure a échoué : les minutes suivantes sont vides, pas calmes.</summary>
    public static bool Interrupted => Unbalanced;

    /// <summary>Lit et vide un emplacement hors du relevé par minute (calibration).</summary>
    public static (long Ticks, long Alloc, int Calls) TakeSlot(int slot)
    {
        var taken = (Stack.Ticks[slot], Stack.Alloc[slot], Stack.Calls[slot]);
        Stack.Ticks[slot] = 0; Stack.Alloc[slot] = 0; Stack.Calls[slot] = 0; Stack.MaxTicks[slot] = 0;
        return taken;
    }

    public static void End()
    {
        if (Unbalanced || Environment.CurrentManagedThreadId != MainThreadId) return;
        try
        {
            // Un patch ou une section resté ouvert sous un gestionnaire : son
            // temps serait versé à l'événement. Même règle que PopPatch, dans l'autre sens.
            if (Stack.TopSlot >= 0 && SlotKind[Stack.TopSlot] is "patch" or "pack")
            {
                Fail($"fin d'événement, mais le sommet de la pile est un {SlotKind[Stack.TopSlot]}");
                return;
            }
            EndCore();
        }
        catch (Exception ex)
        {
            Fail($"End a levé {ex.GetType().Name} : {ex.Message}");
        }
    }

    private static void EndCore() =>
        Stack.Pop(Stopwatch.GetTimestamp(), GC.GetAllocatedBytesForCurrentThread());

    /// <summary>L'identifiant du mod : sa propriété `Manifest` (l'interface `IModInfo` ne
    /// porte pas l'instance), sinon sa représentation texte.</summary>
    private static string ModId(object mod) =>
        (mod.GetType().GetProperty("Manifest")?.GetValue(mod) as IManifest)?.UniqueID
        ?? mod.ToString() ?? "?";

    private static int SlotFor(object mod, object managedEvent)
    {
        if (Slots.TryGetValue((mod, managedEvent), out int slot)) return slot;
        // Chaque événement est un type générique fermé distinct : la propriété
        // se résout sur le type reçu, jamais sur un type mis en cache.
        string name = managedEvent.GetType().GetProperty("EventName")?.GetValue(managedEvent) as string ?? "?";
        slot = AddSlot(ModId(mod), name, isPatch: false);
        Slots[(mod, managedEvent)] = slot;
        return slot;
    }

    private static int AddSlot(string mod, string label, bool isPatch, bool phaseOnly = false, string kind = "event")
    {
        int slot = SlotMod.Count;
        SlotMod.Add(mod);
        SlotEvent.Add(label);
        SlotKind.Add(isPatch ? "patch" : kind);
        Stack.AddSlot(phaseOnly);
        return slot;
    }

    /// <summary>`PatchMs` : la part de `SelfMs` passée dans les patches Harmony du mod (D4-T5, opt-in).</summary>
    public record ModCost(string Mod, double SelfMs, double PatchMs, double MsPerSecond, double MaxMs, long AllocKB, int Calls,
                          List<EventCost> Events);
    public record EventCost(string Event, double SelfMs, double MaxMs, long AllocKB, int Calls);

    /// <summary>Le relevé de la fenêtre, trié par temps propre, puis remise à zéro.</summary>
    public static List<ModCost> Drain(double wallSeconds)
    {
        if (Unbalanced && !InterruptLogged)
        {
            InterruptLogged = true;
            Monitor.Log($"Coût par mod interrompu ({InterruptReason}) : les chiffres s'arrêtent là. Détail : interruption.txt", LogLevel.Warn);
        }
        double msPerTick = 1000.0 / Stopwatch.Frequency;
        var byMod = new Dictionary<string, List<int>>();
        for (int i = 0; i < SlotMod.Count; i++)
        {
            if (Stack.Calls[i] == 0) continue;
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
                ticks += Stack.Ticks[i]; alloc += Stack.Alloc[i]; calls += Stack.Calls[i];
                if (SlotKind[i] == "patch") patchTicks += Stack.Ticks[i];
                if (Stack.MaxTicks[i] > max) max = Stack.MaxTicks[i];
                events.Add(new EventCost(SlotEvent[i], Math.Round(Stack.Ticks[i] * msPerTick, 2),
                    Math.Round(Stack.MaxTicks[i] * msPerTick, 2), Stack.Alloc[i] / 1024, Stack.Calls[i]));
            }
            events.Sort((a, b) => b.SelfMs.CompareTo(a.SelfMs));
            double selfMs = ticks * msPerTick;
            result.Add(new ModCost(mod, Math.Round(selfMs, 2), Math.Round(patchTicks * msPerTick, 2), Math.Round(selfMs / Math.Max(wallSeconds, 0.001), 3),
                Math.Round(max * msPerTick, 2), alloc / 1024, calls, events));
        }
        result.Sort((a, b) => b.SelfMs.CompareTo(a.SelfMs));
        Stack.ClearMinute();
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
