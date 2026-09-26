using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using HarmonyLib;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// Chaque méthode patchée et ses propriétaires, lue dans Harmony même — la
/// source que la commande SMAPI `harmony_summary` affiche. Le propriétaire est
/// l'identifiant passé à `new Harmony(id)`, presque toujours l'UniqueID du mod.
/// </summary>
internal static class HarmonyMap
{
    private record PatchEntry(string Kind, string Owner, string? OwnerName, int Priority, string Patch);
    private record MethodEntry(string Method, string DeclaringAssembly, List<PatchEntry> Patches);
    private record LoadedMod(string UniqueID, string Name, string Version);
    private record Map(string Stage, string CapturedAt, string SmapiVersion, string GameVersion,
                       List<LoadedMod> Mods, List<MethodEntry> Methods);

    /// <summary>Entrée par méthode patchée, null quand elle ne porte que nos enveloppes.</summary>
    private static readonly Dictionary<MethodBase, MethodEntry?> Entries = new();
    private static readonly PatchState State = new();
    private static bool Written;

    /// <summary>
    /// Ne relit que les méthodes dont les patches ont changé (<see cref="PatchState"/>)
    /// et n'écrit rien si aucune n'a changé, sauf <paramref name="force"/>
    /// (commande console). Le champ `Stage` garde alors l'étape de la dernière
    /// écriture.
    /// </summary>
    public static void Write(IModHelper helper, IMonitor monitor, string stage, bool force = false)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            string? NameOf(string owner) => helper.ModRegistry.Get(owner)?.Manifest.Name;

            List<MethodBase>? changed = State.Changed(out List<MethodBase> removed);
            string path = Path.Combine(ModEntry.OutputDir, "harmony-map.json");
            if (changed is null)
            {
                Entries.Clear();
                changed = Harmony.GetAllPatchedMethods().ToList();
            }
            else if (changed.Count == 0 && removed.Count == 0 && Written && !force)
            {
                State.Commit();
                monitor.Log($"Carte Harmony ({stage}) inchangée, {watch.ElapsedMilliseconds} ms.", LogLevel.Trace);
                return;
            }
            foreach (MethodBase method in removed) Entries.Remove(method);
            foreach (MethodBase method in changed)
                Entries[method] = Build(method, NameOf);
            State.Commit();

            var methods = Entries.Values.OfType<MethodEntry>().ToList();
            methods.Sort((a, b) => string.CompareOrdinal(a.Method, b.Method));

            var mods = helper.ModRegistry.GetAll()
                .Select(m => new LoadedMod(m.Manifest.UniqueID, m.Manifest.Name, m.Manifest.Version.ToString()))
                .OrderBy(m => m.UniqueID, StringComparer.OrdinalIgnoreCase)
                .ToList();

            var map = new Map(stage, DateTimeOffset.Now.ToString("o"),
                Constants.ApiVersion.ToString(), StardewValley.Game1.version, mods, methods);
            File.WriteAllText(path, JsonSerializer.Serialize(map, new JsonSerializerOptions { WriteIndented = true }));
            Written = true;
            monitor.Log($"Carte Harmony ({stage}) : {methods.Count} méthodes patchées, {mods.Count} mods, "
                        + $"{changed.Count} relues, {watch.ElapsedMilliseconds} ms → {path}", LogLevel.Info);
        }
        catch (Exception ex)
        {
            monitor.Log($"Carte Harmony ({stage}) impossible : {ex}", LogLevel.Warn);
        }
    }

    private static MethodEntry? Build(MethodBase method, Func<string, string?> nameOf)
    {
        Patches? info = Harmony.GetPatchInfo(method);
        if (info is null) return null;
        var patches = new List<PatchEntry>();
        void Add(string kind, IEnumerable<Patch> list)
        {
            // Nos enveloppes de mesure (D4-T5) ne sont pas des patches du parc.
            foreach (Patch p in list.Where(p => p.owner != PatchCosts.WrapperId))
                patches.Add(new PatchEntry(kind, p.owner, nameOf(p.owner), p.priority,
                    $"{p.PatchMethod.DeclaringType?.FullName}.{p.PatchMethod.Name}"));
        }
        Add("prefix", info.Prefixes);
        Add("postfix", info.Postfixes);
        Add("transpiler", info.Transpilers);
        Add("finalizer", info.Finalizers);
        if (patches.Count == 0) return null;
        return new MethodEntry(Describe(method), method.DeclaringType?.Assembly.GetName().Name ?? "?", patches);
    }

    /// <summary>`Type.Méthode(TypeParam, …)` : la signature distingue les surcharges.</summary>
    private static string Describe(MethodBase method)
    {
        string parameters = string.Join(", ", method.GetParameters().Select(p => p.ParameterType.Name));
        return $"{method.DeclaringType?.FullName}.{method.Name}({parameters})";
    }
}
