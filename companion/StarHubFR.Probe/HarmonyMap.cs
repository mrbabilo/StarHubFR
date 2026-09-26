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

    public static void Write(IModHelper helper, IMonitor monitor, string stage)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            string? NameOf(string owner) => helper.ModRegistry.Get(owner)?.Manifest.Name;

            var methods = new List<MethodEntry>();
            foreach (MethodBase method in Harmony.GetAllPatchedMethods())
            {
                Patches? info = Harmony.GetPatchInfo(method);
                if (info is null) continue;
                var patches = new List<PatchEntry>();
                void Add(string kind, IEnumerable<Patch> list)
                {
                    // Nos enveloppes de mesure (D4-T5) ne sont pas des patches du parc.
                    foreach (Patch p in list.Where(p => p.owner != PatchCosts.WrapperId))
                        patches.Add(new PatchEntry(kind, p.owner, NameOf(p.owner), p.priority,
                            $"{p.PatchMethod.DeclaringType?.FullName}.{p.PatchMethod.Name}"));
                }
                Add("prefix", info.Prefixes);
                Add("postfix", info.Postfixes);
                Add("transpiler", info.Transpilers);
                Add("finalizer", info.Finalizers);
                if (patches.Count == 0) continue;
                methods.Add(new MethodEntry(Describe(method),
                    method.DeclaringType?.Assembly.GetName().Name ?? "?", patches));
            }
            methods.Sort((a, b) => string.CompareOrdinal(a.Method, b.Method));

            var mods = helper.ModRegistry.GetAll()
                .Select(m => new LoadedMod(m.Manifest.UniqueID, m.Manifest.Name, m.Manifest.Version.ToString()))
                .OrderBy(m => m.UniqueID, StringComparer.OrdinalIgnoreCase)
                .ToList();

            var map = new Map(stage, DateTimeOffset.Now.ToString("o"),
                Constants.ApiVersion.ToString(), StardewValley.Game1.version, mods, methods);
            string path = Path.Combine(ModEntry.OutputDir, "harmony-map.json");
            File.WriteAllText(path, JsonSerializer.Serialize(map, new JsonSerializerOptions { WriteIndented = true }));
            monitor.Log($"Carte Harmony ({stage}) : {methods.Count} méthodes patchées, {mods.Count} mods, {watch.ElapsedMilliseconds} ms → {path}", LogLevel.Info);
        }
        catch (Exception ex)
        {
            monitor.Log($"Carte Harmony ({stage}) impossible : {ex}", LogLevel.Warn);
        }
    }

    /// <summary>`Type.Méthode(TypeParam, …)` : la signature distingue les surcharges.</summary>
    private static string Describe(MethodBase method)
    {
        string parameters = string.Join(", ", method.GetParameters().Select(p => p.ParameterType.Name));
        return $"{method.DeclaringType?.FullName}.{method.Name}({parameters})";
    }
}
