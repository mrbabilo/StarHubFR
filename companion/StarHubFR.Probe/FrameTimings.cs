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

    private static double LastDrawStartMs = -1;
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
        if (Clock.Elapsed.TotalMilliseconds - WindowStartMs >= WindowMs) FlushNow();
    }

    private static void StartUpdate() => Update.Restart();

    private static void StopUpdate()
    {
        Update.Stop();
        UpdateMs.Add((float)Update.Elapsed.TotalMilliseconds);
    }

    private record Stat(int Count, double Avg, double P50, double P99, double Max);
    private record Line(string At, double WallSeconds, double Fps, Stat? FrameInterval, Stat? Draw, Stat? Update,
                        long HeapMB, int Gen0, int Gen1, int Gen2, double GcPauseMs, double GcMaxPauseMs,
                        string? Location, int? GameTime, string? Menu);

    public static void FlushNow()
    {
        try
        {
            double wall = (Clock.Elapsed.TotalMilliseconds - WindowStartMs) / 1000;
            if (wall <= 0 || FrameIntervalMs.Count == 0) { ResetWindow(); return; }
            var (pauseMs, maxPauseMs) = GcPauses.Drain();
            var line = new Line(
                DateTimeOffset.Now.ToString("o"),
                Math.Round(wall, 2),
                Math.Round(FrameIntervalMs.Count / wall, 1),
                Summarize(FrameIntervalMs), Summarize(DrawMs), Summarize(UpdateMs),
                GC.GetTotalMemory(false) / (1024 * 1024),
                GC.CollectionCount(0) - Gen0, GC.CollectionCount(1) - Gen1, GC.CollectionCount(2) - Gen2,
                Math.Round(pauseMs, 2), Math.Round(maxPauseMs, 2),
                Context.IsWorldReady ? Game1.currentLocation?.NameOrUniqueName : null,
                Context.IsWorldReady ? Game1.timeOfDay : null,
                Game1.activeClickableMenu?.GetType().FullName);
            File.AppendAllText(Path.Combine(ModEntry.OutputDir, "timings.jsonl"),
                JsonSerializer.Serialize(line) + "\n");
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
        WindowStartMs = Clock.Elapsed.TotalMilliseconds;
        Gen0 = GC.CollectionCount(0);
        Gen1 = GC.CollectionCount(1);
        Gen2 = GC.CollectionCount(2);
    }
}
