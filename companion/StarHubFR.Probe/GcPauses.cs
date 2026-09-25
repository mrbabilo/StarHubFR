// Adapté du mod Profiler — Copyright (c) 2022 SinZ, licence MIT.
// https://github.com/SinZ163/StardewMods — texte complet : LICENSE-THIRD-PARTY.md
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Tracing;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// Durée des pauses du ramasse-miettes, lue dans les événements du runtime
/// .NET — technique reprise de `GcEventListener.cs` du mod Profiler de SinZ
/// (MIT, voir LICENSE-THIRD-PARTY.md). Les rappels arrivent sur un autre fil
/// que le jeu : tout passe sous verrou.
/// </summary>
internal sealed class GcPauses : EventListener
{
    private const int KeywordGC = 1;
    private static GcPauses? Instance;
    private static IMonitor? Monitor;

    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly ConcurrentDictionary<uint, double> started = new();
    private readonly object gate = new();
    private double totalMs, maxMs;

    public static void Start(IMonitor monitor)
    {
        Monitor = monitor;
        Instance = new GcPauses();
    }

    /// <summary>Le cumul et la plus longue pause depuis le dernier appel.</summary>
    public static (double Total, double Max) Drain()
    {
        if (Instance is null) return (0, 0);
        lock (Instance.gate)
        {
            var result = (Instance.totalMs, Instance.maxMs);
            Instance.totalMs = 0;
            Instance.maxMs = 0;
            return result;
        }
    }

    protected override void OnEventSourceCreated(EventSource source)
    {
        try
        {
            if (source.Name == "Microsoft-Windows-DotNETRuntime")
                EnableEvents(source, EventLevel.Informational, (EventKeywords)KeywordGC);
        }
        catch (Exception ex)
        {
            Monitor?.Log($"Pauses GC non mesurées : {ex.Message}", LogLevel.Trace);
        }
    }

    protected override void OnEventWritten(EventWrittenEventArgs e)
    {
        if (e.EventName is null || e.Payload is null || e.PayloadNames is null) return;
        int countIndex = e.PayloadNames.IndexOf("Count");
        if (countIndex < 0) return;
        uint count = Convert.ToUInt32(e.Payload[countIndex]);
        if (e.EventName.Contains("GCStart"))
        {
            started[count] = clock.Elapsed.TotalMilliseconds;
        }
        else if (e.EventName.Contains("GCEnd") && started.TryRemove(count, out double at))
        {
            double pause = clock.Elapsed.TotalMilliseconds - at;
            lock (gate)
            {
                totalMs += pause;
                if (pause > maxMs) maxMs = pause;
            }
        }
    }
}
