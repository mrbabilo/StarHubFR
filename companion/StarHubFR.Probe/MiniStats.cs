using System;
using System.Collections.Generic;
using System.Diagnostics;
using StardewModdingAPI;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>P1 T5 — opt-in : FPS courant, P50/P99 glissants sur 60 s, jeu de
/// travail du processus — coin haut droit, rafraîchi à la seconde. Observation
/// instantanée : ne partage pas le compteur « minutes gardées » (la mesure
/// close vit son propre rythme, 30–35 s de décalage connu).
///
/// UltraSmooth 2.4.14 = référence d'aspect uniquement (permissions Nexus du
/// mod 50971 : aucune réutilisation de fichier, vérifié le 2026-10-11) — ce
/// fichier est écrit neuf.</summary>
internal static class MiniStats
{
    private static int ticksSinceRender;
    private static readonly Queue<double> frameMs = new();
    private static string text = "";

    /// <summary>Deux événements que `GuidedBanner` utilise déjà : dessiné
    /// après lui, coin opposé.</summary>
    public static void Initialize(IModHelper helper)
    {
        helper.Events.Display.RenderedHud += (_, e) =>
        {
            if (Game1.activeClickableMenu is null) Draw(e.SpriteBatch);
        };
        helper.Events.Display.RenderedActiveMenu += (_, e) => Draw(e.SpriteBatch);
    }

    public static void OnTicked(bool enabled)
    {
        if (!MiniStatsRule.ShouldRender(++ticksSinceRender, enabled)) return;
        ticksSinceRender = 0;
        frameMs.Enqueue(FrameTimings.LastFrameMs);
        while (frameMs.Count > 3600) frameMs.Dequeue();   // ~60 s à 60 FPS
        text = Build();
    }

    internal static string Build()
    {
        var sorted = new List<double>(frameMs); sorted.Sort();
        double p50 = Percentile(sorted, 0.50);
        double p99 = Percentile(sorted, 0.99);
        double ws = Process.GetCurrentProcess().WorkingSet64 / (1024.0 * 1024.0);
        double fps = p50 <= 0 ? 0 : 1000.0 / p50;
        return $"FPS {fps:F0}  P50 {p50:F1} ms  P99 {p99:F1} ms  RAM {ws:F0} MB";
    }

    private static double Percentile(List<double> sorted, double q)
    {
        if (sorted.Count == 0) return 0;
        int index = (int)Math.Clamp(q * (sorted.Count - 1), 0, sorted.Count - 1);
        return sorted[index];
    }

    private static void Draw(Microsoft.Xna.Framework.Graphics.SpriteBatch batch)
    {
        if (text.Length == 0) return;
        int x = Game1.viewport.Width - (int)Game1.dialogueFont.MeasureString(text).X - 16;
        batch.DrawString(Game1.dialogueFont, text, new Microsoft.Xna.Framework.Vector2(x + 1, 17),
            Microsoft.Xna.Framework.Color.Black * 0.6f);
        batch.DrawString(Game1.dialogueFont, text, new Microsoft.Xna.Framework.Vector2(x, 16),
            Microsoft.Xna.Framework.Color.White);
    }
}
