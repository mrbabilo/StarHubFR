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
}
