namespace StarHubFR.Probe;

/// <summary>
/// Quand réécrire `gmcm-options.json` : le registre de GMCM est figé après
/// `GameLaunched` (les mods s'y inscrivent au lancement) et la langue ne
/// bouge pas en cours de partie — même registre et même langue, l'export de
/// 4,4 Mo ne se réécrit pas à chaque chargement de sauvegarde. Pur : rien de
/// SMAPI, testé hors jeu.
/// </summary>
public static class GmcmExportRule
{
    public static bool ShouldWrite(int? exportedMods, string? exportedLanguage,
                                   int registryMods, string language, bool force) =>
        force || exportedMods != registryMods || exportedLanguage != language;
}
