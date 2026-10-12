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

    /// <summary>Le saut ne tire qu'en partie, côté hôte, hors cinématique et
    /// hors menu. La minute qui le contient reste exclue (« nuit » : l'horloge
    /// recule) — voulu : elle porte la rafale de ~108 mises à jour d'horloge
    /// d'une seule trame, pas représentative. Une minute perdue par journée de
    /// jeu, contre les cinq ou six que coûtent le sommeil et sa cinématique.</summary>
    public static bool ShouldSkipNightNow(int timeOfDay, bool worldReady, bool mainPlayer, bool eventUp, bool menuOpen) =>
        worldReady && mainPlayer && !eventUp && !menuOpen && ShouldSkipNight(timeOfDay);
    public static bool ShouldExit(GuidedOutcome outcome) => outcome is GuidedOutcome.Stable or GuidedOutcome.Noisy;
}
