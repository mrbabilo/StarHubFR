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
///
/// ⚠️ Un GC d'arrière-plan (`Type` = 1) court **pendant** que le jeu tourne :
/// sa durée n'est pas une pause. La v0.1 les additionnait et annonçait 5 s de
/// « pause » par minute, alors que la pire trame en durait 0,2. Comme chez
/// Profiler, le type sépare les deux.
/// </summary>
internal sealed class GcPauses : EventListener
{
    private const int KeywordGC = 1;
    private static GcPauses? Instance;
    private static IMonitor? Monitor;

    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly ConcurrentDictionary<uint, (double At, uint Type)> started = new();
    private readonly object gate = new();
    private double totalMs, maxMs, backgroundMs;

    public static void Start(IMonitor monitor)
    {
        Monitor = monitor;
        Instance = new GcPauses();
    }

    /// <summary>Le cumul et la plus longue pause depuis le dernier appel.</summary>
    /// <summary>Pauses bloquantes (cumul, max) et durée des GC d'arrière-plan, depuis le dernier appel.</summary>
    public static (double Blocking, double BlockingMax, double Background) Drain()
    {
        if (Instance is null) return (0, 0, 0);
        lock (Instance.gate)
        {
            var result = (Instance.totalMs, Instance.maxMs, Instance.backgroundMs);
            Instance.totalMs = 0;
            Instance.maxMs = 0;
            Instance.backgroundMs = 0;
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
            int typeIndex = e.PayloadNames.IndexOf("Type");
            uint type = typeIndex >= 0 ? Convert.ToUInt32(e.Payload[typeIndex]) : 0;
            started[count] = (clock.Elapsed.TotalMilliseconds, type);
        }
        else if (e.EventName.Contains("GCEnd") && started.TryRemove(count, out var begun))
        {
            double duration = clock.Elapsed.TotalMilliseconds - begun.At;
            lock (gate)
            {
                if (begun.Type == 1)
                {
                    backgroundMs += duration;
                }
                else
                {
                    totalMs += duration;
                    if (duration > maxMs) maxMs = duration;
                }
            }
        }
    }
}
