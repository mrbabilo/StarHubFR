using System.Collections.Generic;
using System.Linq;
using StardewModdingAPI;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>
/// D4-T9 — charge de la scène : les collections du lieu courant comptées au
/// moment d'écrire la ligne de minute (≈ µs, une fois par minute). Compter à
/// chaque dessin, comme Stardropium, fausserait le temps de trame que la
/// sonde mesure précisément ; l'inventaire de ses `TelemetryMetrics` a servi
/// à choisir ce qui décrit une scène.
///
/// L'onglet Performances s'en sert pour dire ce qui explique une minute
/// lente (« 312 meubles, 48 lumières ») et, dans une comparaison avant/après,
/// distinguer un mod coûteux d'une scène plus chargée.
/// </summary>
internal static class SceneCounts
{
    /// <summary>
    /// Les compteurs de la scène du lieu courant, hors monde (`Context.IsWorldReady`
    /// faux, écran titre ou chargement) : `null`, comme `Location`.
    /// `Game1.currentLightSources` est global au processus : en solo, c'est la
    /// lumière affichée ; les clés sont stables, l'app les nomme.
    /// </summary>
    internal static Dictionary<string, int>? Snapshot()
    {
        if (!Context.IsWorldReady || Game1.currentLocation is not { } location) return null;
        return new Dictionary<string, int>
        {
            ["npcs"] = location.characters.Count,
            ["animals"] = location.animals.Length,
            ["furniture"] = location.furniture.Count,
            ["objects"] = location.objects.Count(),
            ["terrainFeatures"] = location.terrainFeatures.Pairs.Count(),
            ["largeTerrainFeatures"] = location.largeTerrainFeatures.Count,
            ["resourceClumps"] = location.resourceClumps.Count,
            ["lights"] = Game1.currentLightSources?.Count ?? 0,
            ["temporarySprites"] = location.TemporarySprites.Count,
            ["debris"] = location.debris.Count,
            ["locations"] = Game1.locations?.Count ?? 0,
        };
    }
}
