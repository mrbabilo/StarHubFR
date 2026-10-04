using System.IO;
using StardewModdingAPI;
using StardewValley;

namespace StarHubFR.Probe;

/// <summary>
/// Le geste exact de `LoadGameMenu.SaveFileSlot.Activate`, partagé par le
/// benchmark et la mesure guidée (une seule copie : deux gestes qui dérivent
/// se contrediraient).
/// </summary>
internal static class AutoLoad
{
    public static bool Try(string saveName, IMonitor monitor, string context)
    {
        string path = Path.Combine(Constants.SavesPath, saveName, saveName);
        if (!File.Exists(path))
        {
            monitor.Log($"{context} : sauvegarde {saveName} introuvable, poursuite sans chargement.", LogLevel.Warn);
            return false;
        }
        monitor.Log($"{context} : chargement de {saveName}.", LogLevel.Info);
        SaveGame.Load(saveName);
        Game1.exitActiveMenu();
        return true;
    }
}
