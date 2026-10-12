// companion/StarHubFR.Probe.Tests/AutoPilotBannerAndMiniStatsRuleTests.cs
using StarHubFR.Probe;
using Xunit;

namespace StarHubFR.Probe.Tests;

/// <summary>P1 T5 — les règles pures du bandeau enrichi et des mini-stats :
/// pourquoi une minute ne compte pas, par raison, et le rythme de rendu
/// (une fois par seconde, jamais par trame).</summary>
public class BannerAndMiniStatsRuleTests
{
    [Fact]
    public void ExcludedReasonsAccumulateByKind()
    {
        var rule = new GuidedRule(minimumMinutes: 5, maximumMinutes: 15);
        rule.Add(new MinuteFacts(At: "t1", WallSeconds: 60, InactiveTicks: 0, Location: "Farm",
            MenuTicks: null, TickCount: null, GameTime: 100, FrameP50: 16, WorkP50: 1,
            TargetTicks: 3600, PatchesActive: false, ConfigChanged: false),
            MinuteReason.Kept);
        rule.Add(new MinuteFacts(At: "t2", WallSeconds: 60, InactiveTicks: 0, Location: "Farm",
            MenuTicks: 3600, TickCount: 3600, GameTime: 110, FrameP50: 16, WorkP50: 1,
            TargetTicks: 0, PatchesActive: false, ConfigChanged: false),
            MinuteReason.MenuOpen);
        rule.Add(new MinuteFacts(At: "t3", WallSeconds: 60, InactiveTicks: 0, Location: "Farm",
            MenuTicks: 3600, TickCount: 3600, GameTime: 120, FrameP50: 16, WorkP50: 1,
            TargetTicks: 0, PatchesActive: false, ConfigChanged: false),
            MinuteReason.MenuOpen);
        Assert.Equal(2, rule.ExcludedByReason[MinuteReason.MenuOpen]);
        Assert.False(rule.ExcludedByReason.ContainsKey(MinuteReason.Night));
    }

    [Fact]
    public void MiniStatsRenderOncePerSecond()
    {
        Assert.True(MiniStatsRule.ShouldRender(elapsedTicks: 60, enabled: true));
        Assert.False(MiniStatsRule.ShouldRender(elapsedTicks: 59, enabled: true));
        Assert.False(MiniStatsRule.ShouldRender(elapsedTicks: 60, enabled: false));
    }
}
