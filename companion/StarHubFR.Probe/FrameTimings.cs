// Adapté du mod Profiler — Copyright (c) 2022 SinZ, licence MIT.
// https://github.com/SinZ163/StardewMods — texte complet : LICENSE-THIRD-PARTY.md
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using HarmonyLib;
using StardewModdingAPI;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>
/// Temps de dessin et de mise à jour, par trame, sur les minuteurs que le jeu
/// appelle lui-même (`DebugTimings`) — technique reprise de `TimingMetrics.cs`
/// du mod Profiler de SinZ (MIT, voir LICENSE-THIRD-PARTY.md). Le jeu les
/// appelle à chaque trame ; ils ne mesurent que si l'affichage de débogage est
/// actif, d'où nos propres chronomètres dans les postfix.
///
/// Écart voulu avec le rapport d'UltraSmooth : la fenêtre est du **temps
/// réel** (une ligne par minute d'horloge), pas « 3 600 trames ÷ 60 ». À
/// 26 FPS, ses « 60 s » en couvrent 138.
/// </summary>
internal static class FrameTimings
{
    private static IMonitor Monitor = null!;

    private static readonly Stopwatch Clock = Stopwatch.StartNew();
    private static readonly Stopwatch Draw = new();
    private static readonly Stopwatch Update = new();

    private static readonly List<float> DrawMs = new(8192);
    private static readonly List<float> UpdateMs = new(8192);
    private static readonly List<float> FrameIntervalMs = new(8192);

    // La trame vue de MonoGame (v0.2) : `Game.Tick` = attente du pas fixe
    // (`Thread.Sleep(1)` en boucle) + un ou plusieurs `DoUpdate` + `DoDraw`,
    // lequel finit par `EndDraw` → `Platform.Present()` (VSync, GPU).
    private static readonly Stopwatch TickWatch = new();
    private static readonly Stopwatch PartWatch = new();
    private static readonly Stopwatch PresentWatch = new();
    private static double TickUpdateMs, TickDrawMs, TickPresentMs;
    private static int TickUpdates;
    private static readonly List<float> TickMs = new(8192);
    private static readonly List<float> OuterUpdateMs = new(8192);
    private static readonly List<float> OuterDrawMs = new(8192);
    private static readonly List<float> PresentMs = new(8192);
    private static readonly List<float> WaitMs = new(8192);
    private static readonly List<float> UpdatesPerTick = new(8192);
    private static int InactiveTicks;

    private static double LastDrawStartMs = -1;
    private static bool Announced;
    /// <summary>Un lancement = une session : les lignes de deux lancements ne se mélangent pas.</summary>
    private static readonly string Session = DateTimeOffset.Now.ToString("o");
    internal static int LoadedMods;
    private static double WindowStartMs;
    private static int Gen0, Gen1, Gen2;
    private const double WindowMs = 60_000;

    public static void Initialize(Harmony harmony, IMonitor monitor)
    {
        Monitor = monitor;
        Type t = typeof(DebugTimings);
        harmony.Patch(t.GetMethod(nameof(DebugTimings.StartDrawTimer)),
            postfix: new HarmonyMethod(typeof(FrameTimings), nameof(StartDraw)));
        harmony.Patch(t.GetMethod(nameof(DebugTimings.StopDrawTimer)),
            postfix: new HarmonyMethod(typeof(FrameTimings), nameof(StopDraw)));
        harmony.Patch(t.GetMethod(nameof(DebugTimings.StartUpdateTimer)),
            postfix: new HarmonyMethod(typeof(FrameTimings), nameof(StartUpdate)));
        harmony.Patch(t.GetMethod(nameof(DebugTimings.StopUpdateTimer)),
            postfix: new HarmonyMethod(typeof(FrameTimings), nameof(StopUpdate)));

        Type game = typeof(Microsoft.Xna.Framework.Game);
        harmony.Patch(AccessTools.Method(game, "Tick"),
            prefix: new HarmonyMethod(typeof(FrameTimings), nameof(TickStart)),
            postfix: new HarmonyMethod(typeof(FrameTimings), nameof(TickEnd)));
        harmony.Patch(AccessTools.Method(game, "DoUpdate"),
            prefix: new HarmonyMethod(typeof(FrameTimings), nameof(PartStart)),
            postfix: new HarmonyMethod(typeof(FrameTimings), nameof(DoUpdateEnd)));
        harmony.Patch(AccessTools.Method(game, "DoDraw"),
            prefix: new HarmonyMethod(typeof(FrameTimings), nameof(PartStart)),
            postfix: new HarmonyMethod(typeof(FrameTimings), nameof(DoDrawEnd)));
        harmony.Patch(AccessTools.Method(game, "EndDraw"),
            prefix: new HarmonyMethod(typeof(FrameTimings), nameof(PresentStart)),
            postfix: new HarmonyMethod(typeof(FrameTimings), nameof(PresentEnd)));
        ResetWindow();
    }

    private static void StartDraw()
    {
        double now = Clock.Elapsed.TotalMilliseconds;
        // L'intervalle entre deux débuts de dessin : la vraie durée d'une
        // trame à l'écran, attente de VSync comprise.
        if (LastDrawStartMs >= 0) FrameIntervalMs.Add((float)(now - LastDrawStartMs));
        LastDrawStartMs = now;
        Draw.Restart();
    }

    private static void StopDraw()
    {
        Draw.Stop();
        DrawMs.Add((float)Draw.Elapsed.TotalMilliseconds);
        if (!Announced)
        {
            // Sans cette ligne, des postfix qui ne tirent jamais (méthode
            // intégrée par le JIT avant le patch) ne laisseraient qu'un
            // fichier absent.
            Announced = true;
            Monitor.Log("Mesure des trames active.", LogLevel.Info);
            // La fenêtre commence à la première trame, pas à l'Entry : sinon
            // le chargement du jeu la remplit de temps sans trame.
            ResetWindow();
            return;
        }
        if (Clock.Elapsed.TotalMilliseconds - WindowStartMs >= WindowMs) FlushNow();
    }

    private static void TickStart()
    {
        TickUpdateMs = TickDrawMs = TickPresentMs = 0;
        TickUpdates = 0;
        TickWatch.Restart();
    }

    private static void PartStart() => PartWatch.Restart();

    private static void DoUpdateEnd()
    {
        TickUpdateMs += PartWatch.Elapsed.TotalMilliseconds;
        TickUpdates++;
    }

    private static void DoDrawEnd() => TickDrawMs += PartWatch.Elapsed.TotalMilliseconds;

    private static void PresentStart() => PresentWatch.Restart();

    private static void PresentEnd() => TickPresentMs += PresentWatch.Elapsed.TotalMilliseconds;

    private static void TickEnd(Microsoft.Xna.Framework.Game __instance)
    {
        double total = TickWatch.Elapsed.TotalMilliseconds;
        if (!Announced) return;
        TickMs.Add((float)total);
        OuterUpdateMs.Add((float)TickUpdateMs);
        OuterDrawMs.Add((float)TickDrawMs);
        PresentMs.Add((float)TickPresentMs);
        WaitMs.Add((float)Math.Max(0, total - TickUpdateMs - TickDrawMs));
        UpdatesPerTick.Add(TickUpdates);
        // Fenêtre sans focus : MonoGame dort 20 ms par tick (InactiveSleepTime)
        // — taper dans la console SMAPI suffit.
        if (!__instance.IsActive) InactiveTicks++;
    }

    private static void StartUpdate() => Update.Restart();

    private static void StopUpdate()
    {
        Update.Stop();
        UpdateMs.Add((float)Update.Elapsed.TotalMilliseconds);
    }

    private record Stat(int Count, double Avg, double P50, double P99, double Max);
    private record Line(string Session, int LoadedMods, string At, double WallSeconds, double Fps, Stat? FrameInterval, Stat? Draw, Stat? Update,
                        Stat? Tick, Stat? OuterUpdate, Stat? OuterDraw, Stat? Present, Stat? Wait, Stat? UpdatesPerTick, int InactiveTicks,
                        long HeapMB, int Gen0, int Gen1, int Gen2, double BlockingGcMs, double BlockingGcMaxMs, double BackgroundGcMs,
                        string? Location, int? GameTime, string? Menu);

    /// <summary>Pour la commande console : ce que la minute en cours a déjà vu.</summary>
    public static string Status() =>
        $"{FrameIntervalMs.Count} trames, {UpdateMs.Count} mises à jour depuis {(Clock.Elapsed.TotalMilliseconds - WindowStartMs) / 1000:0.0} s.";

    public static void FlushNow()
    {
        try
        {
            double wall = (Clock.Elapsed.TotalMilliseconds - WindowStartMs) / 1000;
            if (wall <= 0 || FrameIntervalMs.Count == 0)
            {
                Monitor.Log($"Aucune trame mesurée en {wall:0.0} s : les minuteurs du jeu ne sont pas interceptés.", LogLevel.Warn);
                ResetWindow();
                return;
            }
            var (pauseMs, maxPauseMs, backgroundMs) = GcPauses.Drain();
            var line = new Line(
                Session, LoadedMods,
                DateTimeOffset.Now.ToString("o"),
                Math.Round(wall, 2),
                Math.Round(FrameIntervalMs.Count / wall, 1),
                Summarize(FrameIntervalMs), Summarize(DrawMs), Summarize(UpdateMs),
                Summarize(TickMs), Summarize(OuterUpdateMs), Summarize(OuterDrawMs), Summarize(PresentMs),
                Summarize(WaitMs), Summarize(UpdatesPerTick), InactiveTicks,
                GC.GetTotalMemory(false) / (1024 * 1024),
                GC.CollectionCount(0) - Gen0, GC.CollectionCount(1) - Gen1, GC.CollectionCount(2) - Gen2,
                Math.Round(pauseMs, 2), Math.Round(maxPauseMs, 2), Math.Round(backgroundMs, 2),
                Context.IsWorldReady ? Game1.currentLocation?.NameOrUniqueName : null,
                Context.IsWorldReady ? Game1.timeOfDay : null,
                Game1.activeClickableMenu?.GetType().FullName);
            File.AppendAllText(Path.Combine(ModEntry.OutputDir, "timings.jsonl"),
                JsonSerializer.Serialize(line) + "\n");
            Monitor.Log($"Mesures écrites : {FrameIntervalMs.Count} trames en {wall:0.0} s ({line.Fps} FPS).", LogLevel.Trace);
        }
        catch (Exception ex)
        {
            Monitor.Log($"Mesures non écrites : {ex.Message}", LogLevel.Trace);
        }
        ResetWindow();
    }

    private static Stat? Summarize(List<float> values)
    {
        if (values.Count == 0) return null;
        float[] sorted = values.ToArray();
        Array.Sort(sorted);
        double sum = 0;
        foreach (float v in sorted) sum += v;
        double At(double q) => sorted[Math.Min(sorted.Length - 1, (int)(q * sorted.Length))];
        return new Stat(sorted.Length, Math.Round(sum / sorted.Length, 2),
            Math.Round(At(0.50), 2), Math.Round(At(0.99), 2), Math.Round(sorted[^1], 2));
    }

    private static void ResetWindow()
    {
        DrawMs.Clear();
        UpdateMs.Clear();
        FrameIntervalMs.Clear();
        TickMs.Clear(); OuterUpdateMs.Clear(); OuterDrawMs.Clear();
        PresentMs.Clear(); WaitMs.Clear(); UpdatesPerTick.Clear();
        InactiveTicks = 0;
        WindowStartMs = Clock.Elapsed.TotalMilliseconds;
        Gen0 = GC.CollectionCount(0);
        Gen1 = GC.CollectionCount(1);
        Gen2 = GC.CollectionCount(2);
    }
}
