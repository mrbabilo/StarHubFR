using System;
using System.Collections.Generic;

namespace StarHubFR.Probe;

/// <summary>
/// Le démarrage des mods par SMAPI (`SCore.LoadMods`, boucle « Launching
/// mods ») vu comme une suite d'horodatages : départ de la boucle, puis fin
/// de chaque `Entry` + `GetApi` (`ModMetadata.SetApi`). Le coût d'un mod est
/// l'intervalle depuis le précédent, **moins** le temps que la sonde a déjà
/// attribué à d'autres mods dedans (`attributedTicks`, monotone) — sinon un
/// asset chargé pendant un `Entry` compterait deux fois. Pur : ni SMAPI ni
/// Harmony, pour les tests hors jeu.
/// </summary>
public sealed class StartupTimeline
{
    private readonly double msPerTick;
    private readonly List<(string Mod, double Exclusive, double Nested)> pending = new();
    private readonly List<(string Mod, double Ms, bool Ok)> loads = new();
    private long loopStart = -1, previous, previousAttributed;
    private long firstLoadStart = -1;

    public StartupTimeline(long ticksPerSecond) => msPerTick = 1000.0 / ticksPerSecond;

    /// <summary>Départ → dernière fin de démarrage vue ; null avant le départ.</summary>
    public double? LoopMs { get; private set; }

    public int Recorded { get; private set; }

    /// <summary>Début du premier chargement vu → fin du dernier ; null sans chargement vu.</summary>
    public double? LoadLoopMs { get; private set; }

    /// <summary>Chargements réussis vus : la couverture de la boucle de chargement.</summary>
    public int LoadsSeen { get; private set; }

    /// <summary>
    /// `SCore.TryLoadMod` (boucle de chargement : manifeste, DLL, réécriture,
    /// instance). La phase n'est pas ouverte pendant cette boucle : rien n'est
    /// imbriqué à retirer, le coût est la durée elle-même.
    /// </summary>
    public void LoadEnded(string? modId, long startTicks, long endTicks, bool ok)
    {
        if (firstLoadStart < 0) firstLoadStart = startTicks;
        loads.Add((string.IsNullOrEmpty(modId) ? "?" : modId, Math.Max(0, (endTicks - startTicks) * msPerTick), ok));
        LoadLoopMs = (endTicks - firstLoadStart) * msPerTick;
        if (ok) LoadsSeen++;
    }

    /// <summary>Premier appel seulement : un `reload_i18n` en partie n'est pas un départ.</summary>
    public void LoopStarted(long now, long attributedTicks)
    {
        if (loopStart >= 0) return;
        loopStart = previous = now;
        previousAttributed = attributedTicks;
    }

    public void EntryEnded(string? modId, long now, long attributedTicks)
    {
        if (loopStart < 0) return;
        double inclusive = (now - previous) * msPerTick;
        double nested = Math.Max(0, (attributedTicks - previousAttributed) * msPerTick);
        pending.Add((string.IsNullOrEmpty(modId) ? "?" : modId, Math.Max(0, inclusive - nested), nested));
        previous = now;
        previousAttributed = attributedTicks;
        LoopMs = (now - loopStart) * msPerTick;
        Recorded++;
    }

    /// <summary>Les coûts accumulés depuis le dernier appel (une phase), sans la sonde.</summary>
    public List<CostLine> TakeCosts(string selfId)
    {
        var lines = new List<CostLine>();
        foreach (var (mod, ms, ok) in loads)
        {
            if (string.Equals(mod, selfId, StringComparison.OrdinalIgnoreCase)) continue;
            lines.Add(new CostLine(mod, "load", ok ? "Load" : "Load (échec)", Math.Round(ms, 2), 0, 1));
        }
        loads.Clear();
        foreach (var (mod, exclusive, nested) in pending)
        {
            if (string.Equals(mod, selfId, StringComparison.OrdinalIgnoreCase)) continue;
            // Le temps imbriqué peut être celui du mod lui-même (son propre
            // gestionnaire d'asset) : « déjà attribué », pas « d'autres mods ».
            string label = nested >= 1 ? $"Entry (+{nested:F0} ms déjà attribués)" : "Entry";
            lines.Add(new CostLine(mod, "entry", label, Math.Round(exclusive, 2), 0, 1));
        }
        pending.Clear();
        return lines;
    }
}
