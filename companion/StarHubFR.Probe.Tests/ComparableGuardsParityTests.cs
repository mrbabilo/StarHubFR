using System.Text.Json;
using StarHubFR.Probe;
using Xunit;

/// Parité avec l'app : `comparable-reasons.json` est écrit par le test Swift
/// `ComparableReasonsGoldenTests` à partir de `ProbeComparableMinutes.filter`.
public class ComparableGuardsParityTests
{
    private static string Fixtures()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "Tests/ProbeFilesTests/Fixtures")))
            dir = dir.Parent;
        Assert.NotNull(dir);
        return Path.Combine(dir!.FullName, "Tests/ProbeFilesTests/Fixtures");
    }

    private sealed record Row(string session, string at, string reason);

    [Fact]
    public void GuardsReproduceTheAppOnTheSharedFixture()
    {
        string dir = Fixtures();
        var golden = JsonSerializer.Deserialize<List<Row>>(File.ReadAllText(Path.Combine(dir, "comparable-reasons.json")))!;
        var expected = golden.ToDictionary(r => (r.session, r.at), r => r.reason);

        var bySession = new Dictionary<string, List<(DateTimeOffset When, MinuteFacts Facts)>>();
        foreach (string text in File.ReadLines(Path.Combine(dir, "timings.jsonl")))
        {
            if (string.IsNullOrWhiteSpace(text)) continue;
            JsonElement root;
            try { root = JsonDocument.Parse(text).RootElement; } catch (JsonException) { continue; }
            string session = root.GetProperty("Session").GetString()!;
            string at = root.GetProperty("At").GetString()!;
            int? Int(string name) => root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : null;
            string? location = root.TryGetProperty("Location", out var loc) && loc.ValueKind == JsonValueKind.String ? loc.GetString() : null;
            int? ticks = root.TryGetProperty("Tick", out var tick) && tick.ValueKind == JsonValueKind.Object ? tick.GetProperty("Count").GetInt32() : null;
            var facts = new MinuteFacts(at, root.GetProperty("WallSeconds").GetDouble(), Int("InactiveTicks") ?? 0,
                                        location, Int("MenuTicks"), ticks, Int("GameTime"), null, null);
            if (!bySession.TryGetValue(session, out var list)) bySession[session] = list = new();
            list.Add((DateTimeOffset.Parse(at), facts));
        }

        int compared = 0;
        foreach (var (session, minutes) in bySession)
        {
            var guards = new ComparableGuards();
            foreach (var (_, facts) in minutes.OrderBy(m => m.When))
            {
                var reason = GuidedRule.ReasonName(guards.Classify(facts));
                // Une minute absente de la référence : la fixture et la référence ont divergé.
                Assert.True(expected.TryGetValue((session, facts.At), out var want),
                            $"minute absente de comparable-reasons.json : {session} {facts.At}");
                Assert.True(want == reason, $"{session} {facts.At} : app « {want} », sonde « {reason} »");
                compared++;
            }
        }
        Assert.Equal(golden.Count, compared);
    }
}
