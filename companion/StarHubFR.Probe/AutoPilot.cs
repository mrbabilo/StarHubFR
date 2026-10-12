using System;
using Microsoft.Xna.Framework;
using StardewModdingAPI;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>P1 — l'exécutant en jeu du plan piloté : warp unique au monde
/// prêt, saut de nuit à minuit, sortie propre à la mesure close (retour au
/// titre puis fermeture du processus — le garde-fou coupe au bout de 10 s).
/// Ne touche jamais `Mods/` (invariant D4).</summary>
internal static class AutoPilot
{
    private static bool warped;
    private static bool exiting;
    private static DateTime exitAskedAt = DateTime.MinValue;

    public static void OnSaveLoaded()
    {
        if (!AutoPilotRule.ShouldWarp(warped, Guided.Active?.AutoPilot == true)) return;
        if (Guided.Active is not { } plan || plan.Warp is not { } warp) return;
        warped = true;
        // Signature mesurée sur StardewValley.dll le 2026-10-11 (Game1 L.9755).
        Game1.warpFarmer(plan.Location, warp.X, warp.Y, false);
    }

    public static void OnTick()
    {
        if (Guided.Active?.AutoPilot != true) return;
        if (AutoPilotRule.ShouldSkipNight(Game1.timeOfDay)) SafelySetTime(AutoPilotRule.MorningTime);
        if (!exiting && AutoPilotRule.ShouldExit(Guided.Rule?.Outcome ?? GuidedOutcome.Running))
        {
            exiting = true;
            exitAskedAt = DateTime.UtcNow;
            // Méthode réelle de StardewValley.dll : `ExitToTitle(Action?)` —
            // `exitToTitle` minuscule est le champ bool qu'elle pose.
            Game1.ExitToTitle();
        }
        if (exiting && DateTime.UtcNow - exitAskedAt > TimeSpan.FromSeconds(10))
            Environment.Exit(0);   // garde-fou : le titre n'a pas rendu la main
    }

    /// <summary>Sur ReturnedToTitle : la mesure est close et écrite — le
    /// processus peut partir.</summary>
    public static void OnReturnedToTitle()
    {
        if (exiting) Environment.Exit(0);
    }

    /// <summary>Copie de SetTimeCommand.SafelySetTime (ConsoleCommands.dll,
    /// décompilée le 2026-10-11) — ne pas réinventer.</summary>
    private static void SafelySetTime(int time)
    {
        int steps = Utility.CalculateMinutesBetweenTimes(Game1.timeOfDay, time) / 10;
        if (steps > 0)
            for (int i = 0; i < steps; i++) Game1.performTenMinuteClockUpdate();
        else if (steps < 0)
            for (int i = 0; i > steps; i--)
            {
                Game1.timeOfDay = Utility.ModifyTime(Game1.timeOfDay, -20);
                Game1.performTenMinuteClockUpdate();
            }
        Game1.outdoorLight = Color.White;
        Game1.ambientLight = Color.White;
        Game1.gameTimeInterval = 0;
        Game1.UpdateGameClock(Game1.currentGameTime);
    }
}
