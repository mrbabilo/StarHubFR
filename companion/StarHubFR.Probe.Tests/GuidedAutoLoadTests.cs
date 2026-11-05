using StarHubFR.Probe;
using Xunit;

public class GuidedAutoLoadTests
{
    /// <summary>Les ticks à l'écran titre jusqu'au déclenchement, `null` si rien ne part.</summary>
    private static int? TicksUntilLoad(GuidedAutoLoad gate, string? plan = "plan", int limit = 1000)
    {
        for (int tick = 1; tick <= limit; tick++)
            if (gate.Tick(plan, onTitle: true, worldReady: false)) return tick;
        return null;
    }

    [Fact]
    public void LoadsAfterFiveSecondsOnTheTitleScreen() =>
        Assert.Equal(GuidedAutoLoad.TitleTicks, TicksUntilLoad(new GuidedAutoLoad()));

    [Fact]
    public void AMissingSaveIsNotRetriedOnEveryTick()
    {
        var gate = new GuidedAutoLoad();
        Assert.NotNull(TicksUntilLoad(gate));
        Assert.Null(TicksUntilLoad(gate));
    }

    [Fact]
    public void ReturningToTheTitleDoesNotReloadTheSamePlan()
    {
        var gate = new GuidedAutoLoad();
        gate.Spend("plan");
        Assert.Null(TicksUntilLoad(gate));
    }

    [Fact]
    public void ANewPlanStartsItsOwnDelay()
    {
        var gate = new GuidedAutoLoad();
        Assert.NotNull(TicksUntilLoad(gate, "first"));
        Assert.Equal(GuidedAutoLoad.TitleTicks, TicksUntilLoad(gate, "second"));
    }

    [Fact]
    public void LeavingTheTitleScreenRestartsTheDelay()
    {
        var gate = new GuidedAutoLoad();
        for (int tick = 1; tick < GuidedAutoLoad.TitleTicks; tick++)
            Assert.False(gate.Tick("plan", onTitle: true, worldReady: false));
        Assert.False(gate.Tick("plan", onTitle: false, worldReady: false));
        Assert.Equal(GuidedAutoLoad.TitleTicks, TicksUntilLoad(gate));
    }

    [Fact]
    public void NothingLoadsWithoutASaveOrOnceInGame()
    {
        Assert.Null(TicksUntilLoad(new GuidedAutoLoad(), plan: null));
        var gate = new GuidedAutoLoad();
        for (int tick = 0; tick < GuidedAutoLoad.TitleTicks * 2; tick++)
            Assert.False(gate.Tick("plan", onTitle: true, worldReady: true));
    }
}
