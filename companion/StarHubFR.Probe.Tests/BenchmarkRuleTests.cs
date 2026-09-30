// companion/StarHubFR.Probe.Tests/BenchmarkRuleTests.cs
using System;
using StarHubFR.Probe;
using Xunit;

public class BenchmarkRuleTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 30, 20, 0, 0, TimeSpan.FromHours(2));

    private static string Json(int version = 1, string run = "r1", string save = "TestOK_444827372_bench",
                               string expires = "2026-09-30T18:10:00Z") =>
        $"{{\"Version\":{version},\"RunId\":\"{run}\",\"SaveName\":\"{save}\",\"ExpiresAt\":\"{expires}\"}}";

    [Fact]
    public void AValidPlanIsRead()
    {
        var plan = BenchmarkRule.Parse(Json(), Now);
        Assert.NotNull(plan);
        Assert.Equal("r1", plan!.RunId);
        Assert.Equal("TestOK_444827372_bench", plan.SaveName);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("{not json")]
    [InlineData("{\"Version\":1}")]
    public void AMissingOrUnreadablePlanIsNoPlan(string? json) => Assert.Null(BenchmarkRule.Parse(json, Now));

    [Fact]
    public void AnotherVersionIsNoPlan() => Assert.Null(BenchmarkRule.Parse(Json(version: 2), Now));

    [Fact]
    public void AnEmptyRunOrSaveIsNoPlan()
    {
        Assert.Null(BenchmarkRule.Parse(Json(run: ""), Now));
        Assert.Null(BenchmarkRule.Parse(Json(save: " "), Now));
    }

    /// Review Focus 1 : un plan oublié par une app tuée ne détourne jamais un lancement manuel.
    [Fact]
    public void AnExpiredPlanIsNoPlan() =>
        Assert.Null(BenchmarkRule.Parse(Json(expires: "2026-09-30T17:59:59Z"), Now));

    [Fact]
    public void LoadsOnlyAfterTheDelayOnTheTitleMenuAndOnce()
    {
        Assert.False(BenchmarkRule.ShouldLoad(null, 99_000, titleMenu: true, alreadyLoaded: false));
        Assert.False(BenchmarkRule.ShouldLoad(50_000, 54_999, titleMenu: true, alreadyLoaded: false));
        Assert.True(BenchmarkRule.ShouldLoad(50_000, 55_000, titleMenu: true, alreadyLoaded: false));
        Assert.False(BenchmarkRule.ShouldLoad(50_000, 55_000, titleMenu: false, alreadyLoaded: false));
        Assert.False(BenchmarkRule.ShouldLoad(50_000, 55_000, titleMenu: true, alreadyLoaded: true));
    }

    [Fact]
    public void QuitsFiveSecondsAfterS9()
    {
        Assert.False(BenchmarkRule.ShouldQuit(null, 999_000));
        Assert.False(BenchmarkRule.ShouldQuit(80_000, 84_999));
        Assert.True(BenchmarkRule.ShouldQuit(80_000, 85_000));
    }
}
