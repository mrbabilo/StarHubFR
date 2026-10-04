using System;
using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using StardewModdingAPI;
using StardewValley;
using StardewValley.Menus;

namespace StarHubFR.Probe;

/// <summary>
/// Le bandeau de la mesure guidée, en haut à gauche. `RenderedHud` sans menu,
/// `RenderedActiveMenu` avec (au-dessus du menu) : deux événements que SMAPI
/// émet en mode interface. Les textes se recalculent au changement d'état,
/// pas à chaque trame.
/// </summary>
internal static class GuidedBanner
{
    private enum State { Hidden, Refused, Stable, Noisy, Menu, Elsewhere, Night, Config, Patches, Starting, Counting }

    private static readonly TimeSpan DoneVisible = TimeSpan.FromSeconds(60);
    private static ITranslationHelper? I18n;
    private static (State State, int Count, string Place, int Version)? cacheKey;
    private static string title = "", status = "";

    public static void Initialize(IModHelper helper)
    {
        I18n = helper.Translation;
        helper.Events.Display.RenderedHud += (_, e) =>
        {
            if (Game1.activeClickableMenu is null) Draw(e.SpriteBatch);
        };
        helper.Events.Display.RenderedActiveMenu += (_, e) => Draw(e.SpriteBatch);
    }

    private static State Current(out int count, out string place)
    {
        count = Guided.Rule?.KeptCount ?? 0;
        place = Guided.Active?.Location ?? "";
        if (Guided.Active is null || !Guided.WindowActive) return State.Hidden;
        if (Guided.RefusedKey is not null) return State.Refused;
        if (Guided.Rule is { } rule && rule.Outcome != GuidedOutcome.Running)
        {
            if (Guided.FinishedAtUtc is DateTime at && DateTime.UtcNow - at > DoneVisible) return State.Hidden;
            return rule.Outcome == GuidedOutcome.Stable ? State.Stable : State.Noisy;
        }
        if (Game1.activeClickableMenu is not null) return State.Menu;
        if (Game1.currentLocation?.NameOrUniqueName != Guided.Rule?.Target) return State.Elsewhere;
        if (Guided.Rule?.JustReset == true) return State.Config;
        return Guided.LastReason switch
        {
            MinuteReason.Night => State.Night,
            MinuteReason.PatchesMeasured => State.Patches,
            _ => count == 0 ? State.Starting : State.Counting,
        };
    }

    private static void Draw(SpriteBatch batch)
    {
        if (I18n is null || !Context.IsWorldReady || Context.ScreenId != 0) return;
        var state = Current(out int count, out string placeId);
        if (state == State.Hidden) return;
        var key = (state, count, placeId, Guided.StateVersion);
        if (cacheKey != key)
        {
            cacheKey = key;
            string place = Game1.getLocationFromName(placeId)?.DisplayName ?? placeId;
            title = I18n.Get("banner.title", new { name = Guided.Active?.Name ?? "" }).ToString();
            status = state switch
            {
                State.Refused => I18n.Get(Guided.RefusedKey!).ToString(),
                State.Stable => I18n.Get("state.stable", new { count }).ToString(),
                State.Noisy => I18n.Get("state.noisy").ToString(),
                State.Menu => I18n.Get("state.menu").ToString(),
                State.Elsewhere => I18n.Get("state.elsewhere", new { place }).ToString(),
                State.Night => I18n.Get("state.night").ToString(),
                State.Config => I18n.Get("state.config").ToString(),
                State.Patches => I18n.Get("state.patches").ToString(),
                // Le décompte vivant vit plus bas (hors cache) : les textes
                // ne portent que les minutes gardées.
                State.Counting when count < GuidedRule.MinimumMinutes =>
                    I18n.Get("state.counting", new { count }).ToString(),
                State.Counting => I18n.Get("state.countingReady", new { count }).ToString(),
                _ => I18n.Get("state.starting").ToString(),
            };
        }
        // Décompte en direct, **hors** du bloc de cache ET sans muter le
        // champ caché : `status` reste le texte de référence, `shown` porte
        // l'append de la trame — muter `status` ré-appendait à chaque trame
        // (« 5:00 · 5:00 · 5:00… », retour d'écran du 2026-10-04). 5:00 →
        // 0:00 en temps de présence réel au lieu cible — l'horloge murale
        // compterait le temps passé ailleurs ou en pause. Disparait au
        // plancher atteint (l'état « prêt » prend le relais).
        string shown = status;
        if (state is State.Starting or State.Counting && count < GuidedRule.MinimumMinutes)
        {
            int remaining = Math.Max(0, GuidedRule.MinimumMinutes * 60 - Guided.PresenceTicks / 60);
            shown = $"{shown} · {remaining / 60}:{remaining % 60:00}";
        }
        var font = Game1.smallFont;
        Vector2 titleSize = font.MeasureString(title), statusSize = font.MeasureString(shown);
        int width = (int)Math.Ceiling(Math.Max(titleSize.X, statusSize.X)) + 48;
        int height = (int)Math.Ceiling(titleSize.Y + statusSize.Y) + 40;
        IClickableMenu.drawTextureBox(batch, 16, 16, width, height, Color.White);
        Utility.drawTextWithShadow(batch, title, font, new Vector2(40, 36), Game1.textColor);
        Utility.drawTextWithShadow(batch, shown, font, new Vector2(40, 36 + titleSize.Y), Game1.textColor);
    }
}
