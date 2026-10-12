namespace StarHubFR.Probe;

/// <summary>P1 — décisions du pilotage, pures et testées hors jeu
/// (`AutoPilotRuleTests`, compilé par lien). L'effet de bord vit dans
/// `AutoPilot.cs`, qui touche Stardew.</summary>
public static class AutoPilotRule
{
    /// <summary>Minuit in-game : la cutscene de sommeil forcé est à 2600,
    /// minuit laisse une minute réelle de marge (spec P1 §6).</summary>
    public const int NightSkipThreshold = 2400;
    public const int MorningTime = 600;

    public static bool ShouldWarp(bool alreadyWarped, bool autoPilot) => autoPilot && !alreadyWarped;
    public static bool ShouldSkipNight(int timeOfDay) => timeOfDay >= NightSkipThreshold;
    public static bool ShouldExit(GuidedOutcome outcome) => outcome is GuidedOutcome.Stable or GuidedOutcome.Noisy;
}
