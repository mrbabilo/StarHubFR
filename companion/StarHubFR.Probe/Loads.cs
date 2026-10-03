using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using HarmonyLib;
using StardewModdingAPI;
using StardewModdingAPI.Enums;
using StardewModdingAPI.Events;
using StardewValley;
using StardewValley.Menus;

namespace StarHubFR.Probe;

/// <summary>
/// D5-B : la durée du lancement (`L0` début du processus → `L4` écran titre
/// prêt) et du chargement d'une sauvegarde (`S0` `SaveGame.Load` → `S9` fin
/// de `DayStarted`), avec le coût par mod et par pack entre deux jalons.
/// Une ligne par chargement dans `loads.jsonl`, écrite à `S10` (joueur libre)
/// ou, à défaut, au retour au titre ou à la fermeture. Spec §3.
/// </summary>
internal static class Loads
{
    private static IMonitor Monitor = null!;
    private static string ProbeVersion = "", SelfId = "";
    private static readonly Stopwatch Clock = new();
    /// <summary>Millisecondes de `L0` (début du processus) à la création de <see cref="Clock"/>.</summary>
    private static double LaunchOffsetMs;
    /// <summary>Enregistrement dont la fenêtre de mesure est ouverte.</summary>
    private static LoadRecordBuilder? Current;
    /// <summary>Chargement arrivé à `S9`, fenêtre fermée, qui attend `S10`.</summary>
    private static LoadRecordBuilder? PendingFinal;
    private static string? FinalMenu;
    private static double SaveStartMs;
    private static bool Reloaded;
    private static bool LoadHookPatched;

    private static string OutputPath => Path.Combine(ModEntry.OutputDir, "loads.jsonl");

    public static void Initialize(IModHelper helper, Harmony harmony, IMonitor monitor, string probeVersion, string selfId)
    {
        Monitor = monitor; ProbeVersion = probeVersion; SelfId = selfId;
        Clock.Start();
        DateTime start = Process.GetCurrentProcess().StartTime;
        LaunchOffsetMs = Math.Max(0, (DateTime.Now - start).TotalMilliseconds);

        Current = new LoadRecordBuilder(LoadKind.Launch, FrameTimings.Session,
            new DateTimeOffset(start).ToString("o"), probeVersion, null, null, false, PatchCosts.Active);
        Current.BenchmarkRun = Benchmark.RunId;
        Current.Mark("L0", 0, Array.Empty<CostLine>());
        StartupHooks.NoteRegistry(helper, selfId);
        // Mods démarrés avant la sonde : leur Entry a eu lieu pendant L0 → L1.
        Current.Mark("L1", LaunchOffsetMs, StartupHooks.Timeline.TakeCosts(selfId));
        Open();

        MethodInfo? load = AccessTools.Method(typeof(SaveGame), nameof(SaveGame.Load), new[] { typeof(string) });
        if (load is not null)
        {
            harmony.Patch(load, prefix: new HarmonyMethod(typeof(Loads), nameof(BeforeSaveLoad)));
            LoadHookPatched = true;
        }

        helper.Events.GameLoop.GameLaunched += OnGameLaunchedFirst;
        helper.Events.GameLoop.GameLaunched += OnGameLaunchedLast;
        helper.Events.GameLoop.UpdateTicked += OnUpdateTickedLast;
        helper.Events.Specialized.LoadStageChanged += OnLoadStageChanged;
        helper.Events.GameLoop.SaveLoaded += OnSaveLoadedLast;
        helper.Events.GameLoop.DayStarted += OnDayStartedLast;
    }

    /// <summary>Millisecondes depuis `L0` (début du processus) : l'horloge unique des jalons.</summary>
    internal static double Now => LaunchOffsetMs + Clock.Elapsed.TotalMilliseconds;

    /// <summary>Benchmark : la ligne part sans attendre S10 (hors du total comparé).</summary>
    public static void FlushNow() => Write();

    private static void Open() { ModCosts.PhaseOpen = true; ContentPackSections.Arm(true); }

    private static void Close()
    {
        if (!ModCosts.PhaseOpen) return;
        ModCosts.PhaseOpen = false;
        ContentPackSections.Arm(false);
    }

    private static void Mark(string name, double ms) => Current?.Mark(name, ms, ModCosts.TakePhase(SelfId));

    [EventPriority((EventPriority)int.MaxValue)]
    private static void OnGameLaunchedFirst(object? sender, GameLaunchedEventArgs e)
    {
        if (Current is null) return;
        // La sonde et les mods démarrés après elle : L1 → L2.
        var costs = ModCosts.TakePhase(SelfId);
        costs.AddRange(StartupHooks.Timeline.TakeCosts(SelfId));
        Current.Mark("L2", Now, costs);
    }

    [EventPriority((EventPriority)int.MinValue)]
    private static void OnGameLaunchedLast(object? sender, GameLaunchedEventArgs e) => Mark("L3", Now);

    [EventPriority((EventPriority)int.MinValue)]
    private static void OnUpdateTickedLast(object? sender, UpdateTickedEventArgs e)
    {
        if (Current is { Kind: LoadKind.Launch } && Game1.activeClickableMenu is TitleMenu)
        {
            Mark("L4", Now);
            Benchmark.MarkL4(Now);
            Write();
            return;
        }
        if (PendingFinal is null) return;
        if (Context.IsPlayerFree)
        {
            PendingFinal.SetFinal(LoadMilestones.FinalSave, Now - SaveStartMs, FinalMenu);
            Write();
        }
        else if (Game1.activeClickableMenu is { } menu)
        {
            FinalMenu = menu.GetType().Name;
        }
    }

    /// <summary>`S0` : le clic sur une sauvegarde (le jeu pose alors `Game1.currentLoader`).</summary>
    private static void BeforeSaveLoad(string filename)
    {
        try
        {
            Write();   // un chargement précédent inachevé, ou en attente de S10
            long? bytes = null;
            string path = Path.Combine(Constants.SavesPath, filename, filename);
            if (File.Exists(path)) bytes = new FileInfo(path).Length;
            SaveStartMs = Now;
            Current = new LoadRecordBuilder(LoadKind.Save, FrameTimings.Session, DateTimeOffset.Now.ToString("o"),
                ProbeVersion, filename, bytes, Reloaded, PatchCosts.Active);
            Current.BenchmarkRun = Benchmark.RunId;
            Reloaded = true;
            Open();
            ModCosts.TakePhase(SelfId);   // rien du menu titre ne compte pour S0 → S1
            Current.Mark("S0", 0, Array.Empty<CostLine>());
        }
        catch (Exception ex)
        {
            Monitor.Log($"Chargement non mesuré : {ex.Message}", LogLevel.Trace);
        }
    }

    private static readonly LoadStage[] Stages =
    {
        LoadStage.SaveParsed, LoadStage.SaveAddedLocations, LoadStage.SaveLoadedBasicInfo,
        LoadStage.SaveLoadedLocations, LoadStage.Preloaded, LoadStage.Loaded, LoadStage.Ready,
    };

    [EventPriority((EventPriority)int.MinValue)]
    private static void OnLoadStageChanged(object? sender, LoadStageChangedEventArgs e)
    {
        if (Current is not { Kind: LoadKind.Save }) return;
        int i = Array.IndexOf(Stages, e.NewStage);
        if (i >= 0) Mark($"S{i + 1}", Now - SaveStartMs);
    }

    [EventPriority((EventPriority)int.MinValue)]
    private static void OnSaveLoadedLast(object? sender, SaveLoadedEventArgs e)
    {
        if (Current is not { Kind: LoadKind.Save }) return;
        Mark("S8", Now - SaveStartMs);
        Current.SetSaveDate($"{Game1.currentSeason} {Game1.dayOfMonth} Y{Game1.year}");
    }

    /// <summary>`S9` : fin du total comparé. La fenêtre se ferme ; `S10` attend le joueur.</summary>
    [EventPriority((EventPriority)int.MinValue)]
    private static void OnDayStartedLast(object? sender, DayStartedEventArgs e)
    {
        if (Current is not { Kind: LoadKind.Save }) return;
        Mark("S9", Now - SaveStartMs);
        Benchmark.MarkS9(Now);   // horloge de Loads.Now, pas l'écart depuis S0
        PendingFinal = Current;
        Current = null;
        Close();
        FinalMenu = null;
    }

    /// <summary>Retour au titre : ce qui est en cours part tel quel (incomplet, ou sans `S10`).</summary>
    public static void Abandon() => Write();

    /// <summary>`ProcessExit` : synchrone, sans journal (celui de SMAPI est fermé).</summary>
    public static void AbandonAtExit()
    {
        try { Write(log: false); }
        catch { }
    }

    /// <summary>Écrit l'enregistrement en cours ou en attente de `S10` ; une ligne par chargement.</summary>
    private static void Write(bool log = true)
    {
        var record = PendingFinal ?? Current;
        PendingFinal = null;
        Current = null;
        Close();
        if (record is null) return;
        record.SetHealth(ContentPackSections.Health, ModCosts.AssetHook,
            LoadHookPatched ? "ok" : "missing", ContentPackSections.OffThreadSections,
            StartupHooks.HealthNow, StartupHooks.LoadHealthNow);
        if (record.Kind == LoadKind.Launch)
        {
            record.EntryLoopMs = StartupHooks.Timeline.LoopMs;
            record.LoadLoopMs = StartupHooks.Timeline.LoadLoopMs;
            record.LoadCoveredMods = StartupHooks.Timeline.LoadsSeen;
            record.LoadTotalMods = StartupHooks.RegistryCount;
            record.ProbeLoadsFirst = StartupHooks.ProbeLoadsFirst;
        }
        if (log) Monitor.Log($"Chargement écrit : {ModCosts.AssetDiagnostic}.", LogLevel.Trace);
        try
        {
            File.AppendAllText(OutputPath, record.ToJsonLine() + "\n");
        }
        catch (Exception ex)
        {
            if (log) Monitor.Log($"Chargement non écrit : {ex.Message}", LogLevel.Trace);
        }
    }
}
