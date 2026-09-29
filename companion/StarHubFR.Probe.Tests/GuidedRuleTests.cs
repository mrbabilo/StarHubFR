using StarHubFR.Probe;
using Xunit;

public class GuidedRuleTests
{
    private static MinuteFacts Minute(int i, string? location = "Farm", int inactive = 0, int menu = 0,
        int ticks = 3600, int? gameTime = null, double frame = 33.3, double work = 12.0,
        double wall = 60, int? target = null, bool patches = false, bool config = false) =>
        new($"2026-09-29T10:{i:00}:00.0000000+02:00", wall, inactive, location, menu, ticks,
            gameTime ?? 600 + i * 10, frame, work, target ?? ticks, patches, config);

    // — Gardes communes (copie de ProbeComparableMinutes.filter) —

    [Fact]
    public void GuardsFollowTheAppOrder()
    {
        var g = new ComparableGuards();
        Assert.Equal(MinuteReason.Title, g.Classify(Minute(0, location: null)));
        Assert.Equal(MinuteReason.FirstAfterTitle, g.Classify(Minute(1)));
        Assert.Equal(MinuteReason.Kept, g.Classify(Minute(2)));
        // Sans focus l'emporte sur tout, lieu absent compris.
        Assert.Equal(MinuteReason.Unfocused, g.Classify(Minute(3, location: null, inactive: 1)));
    }

    [Fact]
    public void MenuShareAtHalfIsExcluded()
    {
        var g = new ComparableGuards();
        g.Classify(Minute(0));
        Assert.Equal(MinuteReason.MenuOpen, g.Classify(Minute(1, menu: 1800, ticks: 3600)));
        Assert.Equal(MinuteReason.Kept, g.Classify(Minute(2, menu: 1799, ticks: 3600)));
    }

    [Fact]
    public void NightIsAnEarlierGameTimeAndTheStateFollowsTheLocation()
    {
        var g = new ComparableGuards();
        g.Classify(Minute(0, gameTime: 2500));
        Assert.Equal(MinuteReason.Night, g.Classify(Minute(1, gameTime: 610)));
        // Une minute écartée (menu) garde « en partie » : pas de nouveau chargement.
        g.Classify(Minute(2, menu: 3600));
        Assert.Equal(MinuteReason.Kept, g.Classify(Minute(3, gameTime: 700)));
    }

    // — Gardes guidées —

    [Fact]
    public void GuidedGuardsAreTestedInOrderAfterTheCommonOnes()
    {
        var rule = new GuidedRule("Farm");
        Assert.Equal(MinuteReason.PatchesMeasured, rule.Add(Minute(0, patches: true, wall: 10, target: 0), MinuteReason.Kept));
        Assert.Equal(MinuteReason.Partial, rule.Add(Minute(1, wall: 44.9, target: 0), MinuteReason.Kept));
        Assert.Equal(MinuteReason.OtherLocation, rule.Add(Minute(2, target: 1799, ticks: 3600), MinuteReason.Kept));
        Assert.Equal(MinuteReason.Kept, rule.Add(Minute(3, target: 1800, ticks: 3600), MinuteReason.Kept));
        // Une garde commune passe telle quelle.
        Assert.Equal(MinuteReason.MenuOpen, rule.Add(Minute(4), MinuteReason.MenuOpen));
        Assert.Equal(new[] { "2026-09-29T10:03:00.0000000+02:00" }, rule.KeptAt);
        Assert.Equal(4, rule.Excluded.Count);
    }

    [Fact]
    public void ConfigChangeRestartsTheCountAndDropsTheCurrentMinute()
    {
        var rule = new GuidedRule("Farm");
        for (int i = 0; i < 3; i++) rule.Add(Minute(i), MinuteReason.Kept);
        Assert.Equal(MinuteReason.ConfigChanged, rule.Add(Minute(3, config: true), MinuteReason.Kept));
        Assert.True(rule.JustReset);
        Assert.Empty(rule.KeptAt);
        Assert.Equal(4, rule.Excluded.Count(e => e.Reason == MinuteReason.ConfigChanged));
        rule.Add(Minute(4), MinuteReason.Kept);
        Assert.False(rule.JustReset);
        Assert.Single(rule.KeptAt);
    }

    // — Arrêt —

    [Fact]
    public void StopsStableAtFiveMinutesWhenWorkIsTight()
    {
        var rule = new GuidedRule("Farm");
        double[] work = { 12.0, 12.2, 11.9, 12.1, 12.0 };
        for (int i = 0; i < 4; i++) rule.Add(Minute(i, work: work[i]), MinuteReason.Kept);
        Assert.Equal(GuidedOutcome.Running, rule.Outcome);
        rule.Add(Minute(4, work: work[4]), MinuteReason.Kept);
        Assert.Equal(GuidedOutcome.Stable, rule.Outcome);
        // Arrêtée : plus rien ne s'ajoute.
        rule.Add(Minute(5), MinuteReason.Kept);
        Assert.Equal(5, rule.KeptAt.Count);
    }

    [Fact]
    public void FrameJumpsDoNotBlockAStableWork()
    {
        // La trame saute d'un multiple de synchro à l'autre (36 → 48 ms) : seul le travail juge.
        var rule = new GuidedRule("Farm");
        double[] frame = { 33.3, 50.0, 33.3, 66.7, 33.3 };
        for (int i = 0; i < 5; i++) rule.Add(Minute(i, frame: frame[i], work: 12.0), MinuteReason.Kept);
        Assert.Equal(GuidedOutcome.Stable, rule.Outcome);
        Assert.True(rule.FrameIqrShare > 0.10);
    }

    [Fact]
    public void StopsNoisyAtFifteen()
    {
        var rule = new GuidedRule("Farm");
        for (int i = 0; i < 15; i++) rule.Add(Minute(i, work: i % 2 == 0 ? 10 : 16), MinuteReason.Kept);
        Assert.Equal(GuidedOutcome.Noisy, rule.Outcome);
        Assert.Equal(15, rule.KeptAt.Count);
    }

    [Fact]
    public void IqrShareUsesTukeyHingesLikeTheApp()
    {
        // ProbeStats : [1,2,3,4,5] → q1 = 2, q3 = 4, médiane 3 ; [1,2,3,4] → 1,5 / 3,5 / 2,5.
        Assert.Equal(2.0 / 3.0, GuidedRule.IqrShare(new double[] { 5, 1, 4, 2, 3 })!.Value, 9);
        Assert.Equal(0.8, GuidedRule.IqrShare(new double[] { 1, 2, 3, 4 })!.Value, 9);
        Assert.Null(GuidedRule.IqrShare(new double[] { 3 }));
    }

    [Fact]
    public void GameTimeRangeCoversKeptMinutes()
    {
        var rule = new GuidedRule("Farm");
        rule.Add(Minute(0, gameTime: 630), MinuteReason.Kept);
        rule.Add(Minute(1, gameTime: 700), MinuteReason.MenuOpen);
        rule.Add(Minute(2, gameTime: 650), MinuteReason.Kept);
        Assert.Equal(630, rule.GameTimeFrom);
        Assert.Equal(650, rule.GameTimeTo);
    }

    [Fact]
    public void ReasonNamesMatchTheFile()
    {
        Assert.Equal("menuOpen", GuidedRule.ReasonName(MinuteReason.MenuOpen));
        Assert.Equal("firstAfterTitle", GuidedRule.ReasonName(MinuteReason.FirstAfterTitle));
        Assert.Equal("otherLocation", GuidedRule.ReasonName(MinuteReason.OtherLocation));
    }
}
