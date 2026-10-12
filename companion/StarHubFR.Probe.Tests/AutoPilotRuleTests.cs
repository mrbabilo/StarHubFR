// companion/StarHubFR.Probe.Tests/AutoPilotRuleTests.cs
using StarHubFR.Probe;
using Xunit;

public class AutoPilotRuleTests
{
    [Fact]
    public void WarpsOnceOnlyWhenAutoPilot()
    {
        Assert.True(AutoPilotRule.ShouldWarp(alreadyWarped: false, autoPilot: true));
        Assert.False(AutoPilotRule.ShouldWarp(alreadyWarped: true, autoPilot: true));
        Assert.False(AutoPilotRule.ShouldWarp(alreadyWarped: false, autoPilot: false));
    }

    [Fact]
    public void SkipsNightAtMidnightNotBefore()
    {
        Assert.False(AutoPilotRule.ShouldSkipNight(2350));
        Assert.True(AutoPilotRule.ShouldSkipNight(2400));
        Assert.True(AutoPilotRule.ShouldSkipNight(2500));
    }

    [Fact]
    public void ExitsWhenMeasurementClosedNotWhileRunning()
    {
        Assert.False(AutoPilotRule.ShouldExit(GuidedOutcome.Running));
        Assert.True(AutoPilotRule.ShouldExit(GuidedOutcome.Stable));
        Assert.True(AutoPilotRule.ShouldExit(GuidedOutcome.Noisy));
    }

    /// M5 — le saut ne tire qu'en partie, côté hôte, hors cinématique et hors
    /// menu : `SafelySetTime` y touche l'horloge de tous les joueurs.
    [Fact]
    public void SkipsNightOnlyInAPlainWorldTick()
    {
        Assert.True(AutoPilotRule.ShouldSkipNightNow(2400, worldReady: true, mainPlayer: true, eventUp: false, menuOpen: false));
        Assert.False(AutoPilotRule.ShouldSkipNightNow(2350, worldReady: true, mainPlayer: true, eventUp: false, menuOpen: false));
        Assert.False(AutoPilotRule.ShouldSkipNightNow(2400, worldReady: false, mainPlayer: true, eventUp: false, menuOpen: false));
        Assert.False(AutoPilotRule.ShouldSkipNightNow(2400, worldReady: true, mainPlayer: false, eventUp: false, menuOpen: false));
        Assert.False(AutoPilotRule.ShouldSkipNightNow(2400, worldReady: true, mainPlayer: true, eventUp: true, menuOpen: false));
        Assert.False(AutoPilotRule.ShouldSkipNightNow(2400, worldReady: true, mainPlayer: true, eventUp: false, menuOpen: true));
    }
}
