namespace StarHubFR.Probe;

/// <summary>P1 T5 — la décision pure des mini-stats, testée hors jeu
/// (`AutoPilotBannerAndMiniStatsRuleTests`, compilé par lien). Le rendu vit
/// dans `MiniStats.cs`.</summary>
public static class MiniStatsRule
{
    /// <summary>Une fois par seconde (60 ticks), jamais par trame
    /// (spec P1 §6 bis).</summary>
    public static bool ShouldRender(int elapsedTicks, bool enabled) => enabled && elapsedTicks >= 60;
}
