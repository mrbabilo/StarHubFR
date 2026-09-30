using System.Collections.Generic;
using System.IO;
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
    public void BenchmarkRunIsWrittenWhenSetAndNullOtherwise()
    {
        var plain = Launch();
        using (var doc = JsonDocument.Parse(plain.ToJsonLine()))
            Assert.Equal(JsonValueKind.Null, doc.RootElement.GetProperty("BenchmarkRun").ValueKind);
        var marked = Launch();
        marked.BenchmarkRun = "r7";
        using (var doc = JsonDocument.Parse(marked.ToJsonLine()))
            Assert.Equal("r7", doc.RootElement.GetProperty("BenchmarkRun").GetString());
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

    [Fact]
    public void WritesTheSwiftFixture()
    {
        const string session = "2026-09-30T20:00:00.0000000+02:00";
        var lines = new List<string>();
        var launch = new LoadRecordBuilder(LoadKind.Launch, session, session, "0.6.0", null, null, false, false);
        launch.Mark("L0", 0, None);
        launch.Mark("L1", 20_100, None);
        launch.Mark("L2", 24_800, None);
        launch.Mark("L3", 29_400, new[] {
            new CostLine("Pathoschild.ContentPatcher", "event", "GameLoop.GameLaunched", 812.3, 41.2, 1),
            new CostLine("FlashShifter.StardewValleyExpandedCP", "pack", "ApplyEdit", 120.4, 3.1, 88) });
        launch.Mark("L4", 57_000, new[] {
            new CostLine("Pathoschild.ContentPatcher", "event", "GameLoop.UpdateTicked", 27_300, 900, 1) });
        launch.SetHealth("ok", "ok", "ok", 0);
        lines.Add(launch.ToJsonLine());

        var save = new LoadRecordBuilder(LoadKind.Save, session, "2026-09-30T20:02:10.0000000+02:00", "0.6.0",
                                         "TestOK_444827372", 33_922_308, false, false);
        double[] at = { 0, 11_000, 52_500, 52_800, 64_900, 65_900, 68_900, 71_900, 72_100, 82_500 };
        for (int i = 0; i < at.Length; i++)
        {
            var costs = i == 2
                ? new[] { new CostLine("Rafseazz.RidgesideVillage", "asset", "AssetEdit", 900, 12, 40),
                          new CostLine("FlashShifter.StardewValleyExpandedCP", "pack", "ApplyLoad", 7_400, 210, 300) }
                : i == 6
                    ? new[] { new CostLine("Pathoschild.AutoForager", "event", "Content.AssetReady", 10_600, 5, 9) }
                    : None;
            save.Mark($"S{i}", at[i], costs);
        }
        save.SetFinal("S10", 101_000, "LetterViewerMenu");
        save.SetSaveDate("spring 22 Y1");
        save.SetHealth("ok", "ok", "ok", 0);
        lines.Add(save.ToJsonLine());

        var cut = new LoadRecordBuilder(LoadKind.Save, session, "2026-09-30T20:10:00.0000000+02:00", "0.6.0",
                                        "TestOK_444827372", 33_922_308, true, false);
        cut.Mark("S0", 0, None);
        cut.Mark("S1", 10_800, None);
        lines.Add(cut.ToJsonLine());

        const string sessionB = "2026-09-30T21:00:00.0000000+02:00";
        var launchB = new LoadRecordBuilder(LoadKind.Launch, sessionB, sessionB, "0.6.0", null, null, false, false);
        foreach (var (name, ms) in new[] { ("L0", 0.0), ("L1", 20_000.0), ("L2", 24_700.0), ("L3", 29_300.0), ("L4", 56_800.0) })
            launchB.Mark(name, ms, None);
        launchB.SetHealth("ok", "ok", "ok", 0);
        lines.Add(launchB.ToJsonLine());

        var saveB = new LoadRecordBuilder(LoadKind.Save, sessionB, "2026-09-30T21:02:10.0000000+02:00", "0.6.0",
                                          "TestOK_444827372", 33_922_308, false, false);
        double[] atB = { 0, 11_000, 52_400, 52_700, 64_800, 65_800, 66_900, 69_900, 70_000, 70_000 };
        for (int i = 0; i < atB.Length; i++)
            saveB.Mark($"S{i}", atB[i], i == 2
                ? new[] { new CostLine("FlashShifter.StardewValleyExpandedCP", "pack", "ApplyLoad", 7_300, 205, 300) }
                : None);
        saveB.SetSaveDate("spring 22 Y1");
        saveB.SetHealth("ok", "ok", "ok", 0);
        lines.Add(saveB.ToJsonLine());
        var bench = new LoadRecordBuilder(LoadKind.Save, sessionB, "2026-09-30T21:10:00.0000000+02:00", "0.7.0",
                                          "TestOK_444827372_bench", 33_922_310, false, false);
        for (int i = 0; i < atB.Length; i++) bench.Mark($"S{i}", atB[i], None);
        bench.SetHealth("ok", "ok", "ok", 0);
        bench.BenchmarkRun = "run-3";
        lines.Add(bench.ToJsonLine());
        lines.Add("{\"Kind\":\"save\",\"Session\":\"2026-09-30T22");

        string target = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
            "../../../../../Tests/ProbeFilesTests/Fixtures/loads.jsonl"));
        File.WriteAllText(target, string.Join("\n", lines) + "\n");
        Assert.True(File.Exists(target));
    }
}
