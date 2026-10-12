using System;
using System.Collections.Generic;
using System.Diagnostics;
using StardewModdingAPI;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>P1 T5 — opt-in : FPS de la dernière seconde, P50/P99 des trames
/// de la minute en cours (fenêtre de `FrameTimings`, 0 à 60 s), jeu de
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
    private static int framesAtLastRender;
    private static readonly Stopwatch sinceRender = Stopwatch.StartNew();
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

    /// <summary>À chaque tick de mise à jour ; le texte se recalcule une fois
    /// par seconde. Option coupée : plus rien à l'écran.</summary>
    public static void OnTicked(bool enabled)
    {
        if (!enabled) { text = ""; return; }
        if (!MiniStatsRule.ShouldRender(++ticksSinceRender, enabled)) return;
        ticksSinceRender = 0;
        var window = FrameTimings.WindowTickMs;
        // FPS de la dernière seconde : les trames ajoutées depuis le dernier
        // rendu, sur le temps réellement écoulé. Fenêtre remise à zéro entre
        // deux (nouvelle minute) : seules les trames de la nouvelle comptent.
        int frames = window.Count >= framesAtLastRender ? window.Count - framesAtLastRender : window.Count;
        double seconds = sinceRender.Elapsed.TotalSeconds;
        framesAtLastRender = window.Count;
        sinceRender.Restart();
        text = Build(window, seconds > 0 ? frames / seconds : 0);
    }

    internal static string Build(IReadOnlyList<float> window, double fps)
    {
        var sorted = new List<float>(window); sorted.Sort();
        double p50 = Percentile(sorted, 0.50);
        double p99 = Percentile(sorted, 0.99);
        double ws = Process.GetCurrentProcess().WorkingSet64 / (1024.0 * 1024.0);
        return $"FPS {fps:F0}  P50 {p50:F1} ms  P99 {p99:F1} ms  RAM {ws:F0} MB";
    }

    private static double Percentile(List<float> sorted, double q)
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
