using StarHubFR.Probe;
using Xunit;

public class CostStackTests
{
    [Fact]
    public void OrdinaryFramesMatchTheOldArithmetic()
    {
        var s = new CostStack();
        int evt = s.AddSlot(phaseOnly: false), child = s.AddSlot(phaseOnly: false);
        s.Push(evt, now: 0, allocNow: 0);
        s.Push(child, 10, 100);
        s.Pop(40, 400);            // enfant : 30 ticks, 300 octets
        s.Pop(100, 1000);          // parent : 100 − 30 = 70
        Assert.Equal(70, s.Ticks[evt]);
        Assert.Equal(700, s.Alloc[evt]);
        Assert.Equal(30, s.Ticks[child]);
        Assert.Equal(1, s.Calls[evt]);
    }

    [Fact]
    public void PackInsideEventIsInvisibleToMinuteCounters()
    {
        var s = new CostStack { PhaseOpen = true };
        int evt = s.AddSlot(false), pack = s.AddSlot(phaseOnly: true);
        s.Push(evt, 0, 0);
        s.Push(pack, 10, 0);
        s.Pop(40, 0);
        s.Pop(100, 0);
        // Minute : comme en 0.5.2, le gestionnaire garde tout.
        Assert.Equal(100, s.Ticks[evt]);
        Assert.Equal(0, s.Ticks[pack]);
        Assert.Equal(0, s.Calls[pack]);
        // Phase : le pack sort du gestionnaire.
        Assert.Equal(70, s.PhaseTicks[evt]);
        Assert.Equal(30, s.PhaseTicks[pack]);
    }

    [Fact]
    public void RootPhaseOnlyFrameCreatesNoMinuteRow()
    {
        var s = new CostStack { PhaseOpen = true };
        int asset = s.AddSlot(phaseOnly: true);
        s.Push(asset, 0, 0);
        s.Pop(50, 0);
        Assert.Equal(0, s.Ticks[asset]);
        Assert.Equal(0, s.CumulativeCalls[asset]);
        Assert.Equal(50, s.PhaseTicks[asset]);
    }

    [Fact]
    public void TransparentFramePassesItsOrdinaryChildrenUp()
    {
        // événement > asset (phase seulement) > événement imbriqué
        var s = new CostStack();
        int outer = s.AddSlot(false), asset = s.AddSlot(true), inner = s.AddSlot(false);
        s.Push(outer, 0, 0);
        s.Push(asset, 10, 0);
        s.Push(inner, 20, 0);
        s.Pop(30, 0);   // inner : 10
        s.Pop(60, 0);   // asset : transparent
        s.Pop(100, 0);  // outer : 100 − 10 (inner) = 90, jamais compté deux fois
        Assert.Equal(10, s.Ticks[inner]);
        Assert.Equal(90, s.Ticks[outer]);
    }

    [Fact]
    public void ClosedPhaseCountsNothing()
    {
        var s = new CostStack();
        int evt = s.AddSlot(false);
        s.Push(evt, 0, 0);
        s.Pop(10, 0);
        Assert.Equal(0, s.PhaseTicks[evt]);
        Assert.Equal(0, s.PhaseCalls[evt]);
    }

    [Fact]
    public void OverflowBeyondMaxDepthIsIgnoredAndBalanced()
    {
        var s = new CostStack();
        int evt = s.AddSlot(false);
        for (int i = 0; i < CostStack.MaxDepth + 3; i++) s.Push(evt, i, 0);
        for (int i = 0; i < CostStack.MaxDepth + 3; i++) s.Pop(1000, 0);
        Assert.Equal(0, s.Depth);
        Assert.Equal(CostStack.MaxDepth, s.Calls[evt]);
    }

    [Fact]
    public void SlotsGrowPastTheInitialCapacity()
    {
        var s = new CostStack();
        int last = 0;
        for (int i = 0; i < 300; i++) last = s.AddSlot(i % 2 == 0);
        s.Push(last, 0, 0);
        s.Pop(5, 0);
        Assert.Equal(5, s.Ticks[last]);          // 299 est impair : emplacement ordinaire
    }

    [Fact]
    public void RootFramesFeedAMonotonicCounterWhilePhaseIsOpen()
    {
        var s = new CostStack { PhaseOpen = true };
        int evt = s.AddSlot(false), child = s.AddSlot(false);
        s.Push(evt, 0, 0);
        s.Push(child, 10, 0);
        s.Pop(40, 0);            // enfant : ne compte pas en plus (déjà dans le parent)
        s.Pop(100, 0);           // racine : 100
        Assert.Equal(100, s.PhaseRootTicks);
        s.ClearPhase();          // un jalon vide la phase, jamais le compteur
        Assert.Equal(100, s.PhaseRootTicks);
        s.Push(evt, 200, 0);
        s.Pop(250, 0);
        Assert.Equal(150, s.PhaseRootTicks);
    }

    [Fact]
    public void ClosedPhaseDoesNotFeedTheCounter()
    {
        var s = new CostStack();   // PhaseOpen == false
        int evt = s.AddSlot(false);
        s.Push(evt, 0, 0);
        s.Pop(100, 0);
        Assert.Equal(0, s.PhaseRootTicks);
    }
}
