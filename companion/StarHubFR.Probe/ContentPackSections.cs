using System;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// D5-B : le coût de chaque pack de contenu Content Patcher pendant les
/// chargements. Content Patcher 2.9.1 enveloppe déjà chaque patch appliqué
/// dans `Profiler?.RecordSection(packId, "ApplyLoad"|"ApplyEdit", path)` —
/// son intégration publique avec le mod Profiler (`SinZ.Profiler`). Sans
/// Profiler le champ vaut null. La sonde le pose **pendant les fenêtres de
/// chargement seulement** (hors fenêtre, Content Patcher ne calcule plus
/// `patch.Path.ToString()` : aucun effet d'observateur sur les mesures en jeu)
/// et répond à `RecordSection` à la place de Profiler.
///
/// Types résolus dans l'assembly de Content Patcher : d'autres mods
/// Pathoschild embarquent le même espace `Pathoschild.Stardew.Common`.
/// Si Content Patcher renomme le champ ou la méthode : `Health` reste
/// `"missing"`, dit à l'écran — jamais un zéro muet.
/// </summary>
internal static class ContentPackSections
{
    private static IMonitor Monitor = null!;
    private static FieldInfo? ProfilerField;
    private static readonly List<(object Manager, object Integration)> Managers = new();
    private static bool Armed;
    private static int SectionsSeen;

    public static int OffThreadSections { get; private set; }
    public static string Health => Profiler ? "profiler" : Patched && SectionsSeen > 0 ? "ok" : "missing";
    private static bool Patched, Profiler;

    public static void Initialize(IModHelper helper, Harmony harmony, IMonitor monitor)
    {
        Monitor = monitor;
        // Les deux mods sont déclarés incompatibles : sans Profiler chargé,
        // la couture est à nous ; avec, on n'y touche pas.
        if (helper.ModRegistry.IsLoaded("SinZ.Profiler")) { Profiler = true; return; }
        try
        {
            // `IModInfo` n'expose pas l'instance du mod : l'assembly se trouve par son nom.
            Assembly? asm = helper.ModRegistry.IsLoaded("Pathoschild.ContentPatcher")
                ? Array.Find(AppDomain.CurrentDomain.GetAssemblies(), a => a.GetName().Name == "ContentPatcher")
                : null;
            Type? manager = asm?.GetType("ContentPatcher.Framework.PatchManager");
            Type? integration = asm?.GetType("Pathoschild.Stardew.Common.Integrations.Profiler.ProfilerIntegration");
            ProfilerField = manager is null ? null : AccessTools.Field(manager, "Profiler");
            MethodInfo? record = integration is null ? null : AccessTools.Method(integration, "RecordSection");
            ConstructorInfo[] ctors = manager?.GetConstructors() ?? Array.Empty<ConstructorInfo>();
            ConstructorInfo? ctor = ctors.Length == 1 ? ctors[0] : null;
            if (ProfilerField is null || record is null || ctor is null)
            {
                monitor.Log("Coût par pack indisponible : couture Content Patcher introuvable.", LogLevel.Trace);
                return;
            }
            harmony.Patch(ctor, postfix: new HarmonyMethod(typeof(ContentPackSections), nameof(AfterManager)));
            harmony.Patch(record, prefix: new HarmonyMethod(typeof(ContentPackSections), nameof(BeforeRecord)));
            Patched = true;
        }
        catch (Exception ex)
        {
            monitor.Log($"Coût par pack indisponible : {ex.Message}", LogLevel.Trace);
        }
    }

    /// <summary>Un `PatchManager` créé (création paresseuse, par écran) : retenu avec son intégration.</summary>
    private static void AfterManager(object __instance, object profiler)
    {
        Managers.Add((__instance, profiler));
        if (Armed) ProfilerField!.SetValue(__instance, profiler);
    }

    public static void Arm(bool on)
    {
        Armed = on;
        if (ProfilerField is null) return;
        foreach (var (manager, integration) in Managers)
        {
            try { ProfilerField.SetValue(manager, on ? integration : null); }
            catch (Exception ex) { Monitor.Log($"Couture Content Patcher : {ex.Message}", LogLevel.Trace); }
        }
    }

    /// <summary>Remplace `RecordSection` (qui lèverait : Profiler absent).</summary>
    private static bool BeforeRecord(string modId, string eventType, ref IDisposable? __result)
    {
        if (!ModCosts.OnMainThread)
        {
            // Le chargement de contenu en arrière-plan : compté, jamais mesuré
            // (la pile de mesure est statique, fil du jeu seulement).
            OffThreadSections++;
            __result = NoSection.Instance;
            return false;
        }
        int slot = ModCosts.SectionSlot(modId, eventType);
        ModCosts.PushSection(slot);
        SectionsSeen++;
        __result = new Section(slot);
        return false;
    }

    /// <summary>
    /// Un objet par section : `using` le dispose une fois, à la sortie du patch.
    /// Les sections s'imbriquent (un ApplyEdit peut déclencher un chargement
    /// d'asset qui applique un autre pack) : une instance réutilisée ne saurait
    /// pas quel emplacement dépiler. Une petite allocation par patch appliqué,
    /// pendant les fenêtres seulement.
    /// </summary>
    private sealed class Section : IDisposable
    {
        private readonly int slot;
        public Section(int slot) => this.slot = slot;
        public void Dispose() => ModCosts.PopSection(slot);
    }

    private sealed class NoSection : IDisposable
    {
        public static readonly NoSection Instance = new();
        public void Dispose() { }
    }
}
