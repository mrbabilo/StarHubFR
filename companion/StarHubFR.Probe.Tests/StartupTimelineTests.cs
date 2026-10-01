using StarHubFR.Probe;
using Xunit;

public class StartupTimelineTests
{
    // 1 000 ticks par seconde : 1 tick = 1 ms, lisible.
    private static StartupTimeline Make() => new(ticksPerSecond: 1000);

    [Fact]
    public void EachEntryCostsTheIntervalSinceThePreviousOne()
    {
        var t = Make();
        t.LoopStarted(now: 100, attributedTicks: 0);
        t.EntryEnded("A", now: 130, attributedTicks: 0);
        t.EntryEnded("B", now: 400, attributedTicks: 0);
        var costs = t.TakeCosts("mrbabilo.StarHubFR.Probe");
        Assert.Equal(new[] { ("A", 30.0), ("B", 270.0) }, costs.Select(c => (c.Mod, c.Ms)));
        Assert.All(costs, c => { Assert.Equal("entry", c.Kind); Assert.Equal(1, c.Calls); Assert.Equal("Entry", c.Label); });
        Assert.Equal(300.0, t.LoopMs);
        Assert.Equal(2, t.Recorded);
    }

    [Fact]
    public void TimeAttributedToOtherModsInsideTheIntervalIsSubtracted()
    {
        var t = Make();
        t.LoopStarted(0, attributedTicks: 1_000);
        // B charge un asset : un gestionnaire d'un autre mod y tourne 120 ms.
        t.EntryEnded("B", now: 500, attributedTicks: 1_120);
        var cost = Assert.Single(t.TakeCosts("self"));
        Assert.Equal(380.0, cost.Ms);
        Assert.Equal("Entry (+120 ms déjà attribués)", cost.Label);
    }

    [Fact]
    public void ExclusiveCostNeverGoesNegative()
    {
        var t = Make();
        t.LoopStarted(0, 0);
        t.EntryEnded("A", now: 10, attributedTicks: 50);   // garde : jamais négatif, quoi qu'il arrive
        Assert.Equal(0.0, Assert.Single(t.TakeCosts("self")).Ms);
    }

    [Fact]
    public void TheProbeItselfIsLeftOut()
    {
        var t = Make();
        t.LoopStarted(0, 0);
        t.EntryEnded("mrbabilo.StarHubFR.Probe", 50, 0);
        t.EntryEnded("A", 80, 0);
        var cost = Assert.Single(t.TakeCosts("MRBABILO.StarHubFR.Probe"));
        Assert.Equal(("A", 30.0), (cost.Mod, cost.Ms));
        Assert.Equal(80.0, t.LoopMs);   // la boucle, elle, compte tout
    }

    [Fact]
    public void TakeCostsDrainsSoEachPhaseGetsItsOwnMods()
    {
        var t = Make();
        t.LoopStarted(0, 0);
        t.EntryEnded("A", 10, 0);
        Assert.Single(t.TakeCosts("self"));     // phase L0→L1
        t.EntryEnded("B", 25, 0);
        var later = Assert.Single(t.TakeCosts("self"));   // phase L1→L2
        Assert.Equal(("B", 15.0), (later.Mod, later.Ms));
    }

    [Fact]
    public void NothingBeforeTheLoopStartsAndASecondStartIsIgnored()
    {
        var t = Make();
        t.EntryEnded("early", 5, 0);            // SetApi vu avant le départ : ignoré
        Assert.Empty(t.TakeCosts("self"));
        Assert.Null(t.LoopMs);
        t.LoopStarted(10, 0);
        t.EntryEnded("A", 20, 0);
        t.LoopStarted(500, 0);                  // reload_i18n en partie : pas un nouveau départ
        t.EntryEnded("B", 50, 0);
        Assert.Equal(new[] { 10.0, 30.0 }, t.TakeCosts("self").Select(c => c.Ms));
    }

    [Fact]
    public void AMissingIdIsKeptUnderAPlaceholder()
    {
        var t = Make();
        t.LoopStarted(0, 0);
        t.EntryEnded(null, 10, 0);
        t.EntryEnded("", 20, 0);
        Assert.Equal(new[] { "?", "?" }, t.TakeCosts("self").Select(c => c.Mod));
    }

    /// Un `GetApi` qui lève saute `SetApi` : son temps passe au mod suivant —
    /// limite documentée (spec § 3), la timeline continue sans se dérégler.
    [Fact]
    public void ASkippedModFoldsIntoTheNextOne()
    {
        var t = Make();
        t.LoopStarted(0, 0);
        t.EntryEnded("A", 10, 0);
        // « Broken » : Entry 40 ms, GetApi lève, pas de SetApi.
        t.EntryEnded("C", 70, 0);
        Assert.Equal(new[] { ("A", 10.0), ("C", 60.0) }, t.TakeCosts("self").Select(c => (c.Mod, c.Ms)));
    }
}
