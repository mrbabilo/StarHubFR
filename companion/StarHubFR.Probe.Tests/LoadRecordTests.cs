using System.Text.Json;
using StarHubFR.Probe;
using Xunit;

public class LoadRecordTests
{
    private static LoadRecordBuilder Launch() =>
        new(LoadKind.Launch, "2026-09-30T20:00:00.0000000+02:00", "2026-09-30T20:00:00.0000000+02:00",
            "0.6.0", saveName: null, saveBytes: null, reload: false, patchesMeasured: false);

    private static readonly CostLine[] None = System.Array.Empty<CostLine>();

    [Fact]
    public void AllLaunchMilestonesMakeItComplete()
    {
        var b = Launch();
        b.Mark("L0", 0, None);
        b.Mark("L1", 20_000, None);
        b.Mark("L2", 25_000, None);
        b.Mark("L3", 29_600, new[] { new CostLine("Pathoschild.ContentPatcher", "event", "GameLoop.GameLaunched", 812.3, 41.2, 1) });
        b.Mark("L4", 57_000, None);
        Assert.True(b.Complete);
    }

    [Fact]
    public void AbandonMidLoadIsIncomplete()
    {
        var b = new LoadRecordBuilder(LoadKind.Save, "s", "a", "0.6.0", "TestOK_444827372", 33_922_308, false, false);
        b.Mark("S0", 0, None);
        b.Mark("S1", 11_000, None);
        Assert.False(b.Complete);
        using var doc = JsonDocument.Parse(b.ToJsonLine());
        Assert.False(doc.RootElement.GetProperty("Complete").GetBoolean());
    }

    [Fact]
    public void OutOfOrderMilestoneIsIncomplete()
    {
        var b = Launch();
        foreach (var name in new[] { "L0", "L2", "L1", "L3", "L4" }) b.Mark(name, 1, None);
        Assert.False(b.Complete);
    }

    [Fact]
    public void PhasesJoinConsecutiveMilestonesWithTheirCosts()
    {
        var b = Launch();
        b.Mark("L0", 0, None);
        b.Mark("L1", 20_000, None);
        b.Mark("L2", 25_000, None);
        b.Mark("L3", 29_600, new[] { new CostLine("A", "event", "GameLoop.GameLaunched", 100, 1, 1) });
        b.Mark("L4", 57_000, None);
        using var doc = JsonDocument.Parse(b.ToJsonLine());
        var phases = doc.RootElement.GetProperty("Phases");
        Assert.Equal(4, phases.GetArrayLength());
        var p = phases[2];
        Assert.Equal("L2", p.GetProperty("From").GetString());
        Assert.Equal("L3", p.GetProperty("To").GetString());
        Assert.Equal(4600, p.GetProperty("Ms").GetDouble(), 3);
        Assert.Equal("A", p.GetProperty("Costs")[0].GetProperty("Mod").GetString());
    }

    [Fact]
    public void FinalIsSeparateAndHealthIsWritten()
    {
        var b = new LoadRecordBuilder(LoadKind.Save, "s", "a", "0.6.0", "TestOK_444827372", 33_922_308, false, false);
        for (int i = 0; i <= 9; i++) b.Mark($"S{i}", i * 1000, None);
        b.SetFinal("S10", 18_123, "LetterViewerMenu");
        b.SetSaveDate("spring 22 Y1");
        b.SetHealth("ok", "ok", "ok", 0);
        using var doc = JsonDocument.Parse(b.ToJsonLine());
        var root = doc.RootElement;
        Assert.True(root.GetProperty("Complete").GetBoolean());
        Assert.Equal("save", root.GetProperty("Kind").GetString());
        Assert.Equal("LetterViewerMenu", root.GetProperty("Final").GetProperty("Menu").GetString());
        Assert.Equal(33_922_308, root.GetProperty("SaveBytes").GetInt64());
        Assert.Equal("ok", root.GetProperty("Health").GetProperty("PackSeam").GetString());
        // S10 n'entre pas dans les phases : le total comparé s'arrête à S9.
        Assert.Equal(9, root.GetProperty("Phases").GetArrayLength());
    }
}
