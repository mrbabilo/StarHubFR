using System;
using System.Collections.Generic;

namespace StarHubFR.Probe;

/// <summary>
/// La pile de mesure de <see cref="ModCosts"/> et ses compteurs par
/// emplacement, sans rien de SMAPI : les horodatages et les octets arrivent en
/// paramètres, pour les tests hors jeu.
///
/// Deux jeux de compteurs. **Minute** : relevé de `mod-costs.jsonl`, vidé par
/// `Drain` ; il doit rester celui de 0.5.2. **Phase** (D5-B) : alimenté
/// seulement quand <see cref="PhaseOpen"/>, vidé à chaque jalon de
/// chargement. Un emplacement « phase seulement » (section de pack Content
/// Patcher, rappel d'asset) est transparent pour la minute : son temps reste
/// dans le cadre parent, comme en 0.5.2, et il ne crée aucune ligne.
/// </summary>
public sealed class CostStack
{
    public const int MaxDepth = 64;

    private readonly int[] stackSlot = new int[MaxDepth];
    private readonly long[] stackStart = new long[MaxDepth];
    private readonly long[] stackAlloc = new long[MaxDepth];
    private readonly long[] childMinuteTicks = new long[MaxDepth];
    private readonly long[] childMinuteAlloc = new long[MaxDepth];
    private readonly long[] childPhaseTicks = new long[MaxDepth];
    private readonly long[] childPhaseAlloc = new long[MaxDepth];
    private readonly List<bool> phaseOnly = new();

    public long[] Ticks = new long[256], Alloc = new long[256], MaxTicks = new long[256];
    public int[] Calls = new int[256], CumulativeCalls = new int[256];
    public long[] PhaseTicks = new long[256], PhaseAlloc = new long[256];
    public int[] PhaseCalls = new int[256];

    /// <summary>
    /// Temps total des cadres **racines** refermés pendant une phase ouverte,
    /// jamais remis à zéro : la différence entre deux lectures = ce que la
    /// sonde a attribué entre-temps (démarrage des mods, coût exclusif).
    /// </summary>
    public long PhaseRootTicks { get; private set; }

    public bool PhaseOpen { get; set; }
    public int Depth { get; private set; }
    public int SlotCount => phaseOnly.Count;

    /// <summary>Sommet de la pile ; −1 si elle est vide ou débordée.</summary>
    public int TopSlot => Depth > 0 && Depth <= MaxDepth ? stackSlot[Depth - 1] : -1;
    public int SlotAt(int depth) => stackSlot[depth];
    public bool IsPhaseOnly(int slot) => phaseOnly[slot];

    public int AddSlot(bool phaseOnly)
    {
        int slot = this.phaseOnly.Count;
        this.phaseOnly.Add(phaseOnly);
        if (slot >= Ticks.Length)
        {
            int size = Math.Max(Ticks.Length * 2, slot + 1);
            Array.Resize(ref Ticks, size); Array.Resize(ref Alloc, size); Array.Resize(ref MaxTicks, size);
            Array.Resize(ref Calls, size); Array.Resize(ref CumulativeCalls, size);
            Array.Resize(ref PhaseTicks, size); Array.Resize(ref PhaseAlloc, size); Array.Resize(ref PhaseCalls, size);
        }
        return slot;
    }

    public void Push(int slot, long now, long allocNow)
    {
        if (Depth >= MaxDepth) { Depth++; return; }
        int d = Depth++;
        stackSlot[d] = slot;
        childMinuteTicks[d] = 0; childMinuteAlloc[d] = 0;
        childPhaseTicks[d] = 0; childPhaseAlloc[d] = 0;
        stackAlloc[d] = allocNow;
        stackStart[d] = now;
    }

    public void Pop(long now, long allocNow)
    {
        if (Depth == 0) return;
        int d = --Depth;
        if (d >= MaxDepth) return;
        long total = now - stackStart[d];
        long totalAlloc = allocNow - stackAlloc[d];
        int slot = stackSlot[d];
        bool transparent = phaseOnly[slot];

        if (!transparent)
        {
            long self = Math.Max(0, total - childMinuteTicks[d]);
            Ticks[slot] += self;
            Alloc[slot] += Math.Max(0, totalAlloc - childMinuteAlloc[d]);
            Calls[slot]++;
            CumulativeCalls[slot]++;
            if (self > MaxTicks[slot]) MaxTicks[slot] = self;
        }
        if (PhaseOpen)
        {
            PhaseTicks[slot] += Math.Max(0, total - childPhaseTicks[d]);
            PhaseAlloc[slot] += Math.Max(0, totalAlloc - childPhaseAlloc[d]);
            PhaseCalls[slot]++;
        }
        if (PhaseOpen && d == 0) PhaseRootTicks += total;
        if (d > 0)
        {
            childMinuteTicks[d - 1] += transparent ? childMinuteTicks[d] : total;
            childMinuteAlloc[d - 1] += transparent ? childMinuteAlloc[d] : totalAlloc;
            childPhaseTicks[d - 1] += total;
            childPhaseAlloc[d - 1] += totalAlloc;
        }
    }

    public void ClearMinute()
    {
        Array.Clear(Ticks); Array.Clear(Alloc); Array.Clear(Calls); Array.Clear(MaxTicks);
    }

    public void ClearPhase()
    {
        Array.Clear(PhaseTicks); Array.Clear(PhaseAlloc); Array.Clear(PhaseCalls);
    }
}
