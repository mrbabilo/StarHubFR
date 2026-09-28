using HarmonyLib;
using StardewModdingAPI;

namespace StarHubFR.Probe;

/// <summary>
/// Le dossier d'un mod chargé. `DirectoryPath` est public sur `ModMetadata`,
/// l'implémentation interne de l'`IModInfo` que rend SMAPI ; l'interface ne
/// l'expose pas. Un seul endroit pour cette réflexion (capture GMCM,
/// inventaire).
/// </summary>
internal static class ModDirectory
{
    public static string? Of(IModInfo? info) =>
        info is null ? null : AccessTools.Property(info.GetType(), "DirectoryPath")?.GetValue(info) as string;
}
