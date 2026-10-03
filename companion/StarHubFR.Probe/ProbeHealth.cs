namespace StarHubFR.Probe;

/// <summary>
/// Les valeurs de santé écrites dans `loads.jsonl` (champ `Health`). Avant
/// X119 (2026-10-03), « missing » disait à la fois « accroche cassée » et
/// « rien à observer » : un Content Patcher en pause affichait « Ventilation
/// indisponible », une session sans rappel d'assets accusait SMAPI. L'app ne
/// réagit qu'à « missing » — les autres valeurs restent silencieuses.
/// Pur : rien de SMAPI, testé hors jeu.
/// </summary>
public static class ProbeHealth
{
    /// <summary>
    /// La couture Content Patcher : « profiler » (SinZ.Profiler chargé, la
    /// sonde n'y touche pas), « absent » (Content Patcher hors du parc),
    /// « missing » (Content Patcher là, champ ou méthode introuvable — la
    /// vraie régression), « idle » (posée, aucune section vue — session sans
    /// chargement de pack), « ok ».
    /// </summary>
    public static string PackSeam(bool profiler, bool contentPatcherLoaded, bool seamPatched, bool sectionsSeen)
    {
        if (profiler) return "profiler";
        if (!contentPatcherLoaded) return "absent";
        if (!seamPatched) return "missing";
        return sectionsSeen ? "ok" : "idle";
    }

    /// <summary>
    /// Les rappels d'assets : « missing » (accroche non posée — SMAPI sans
    /// `RequestAssetOperations`), « idle » (posée, aucun rappel vu — rien à
    /// observer), « ok » (rappels mesurés).
    /// </summary>
    public static string AssetHook(bool hookPatched, int callsSeen)
    {
        if (!hookPatched) return "missing";
        return callsSeen > 0 ? "ok" : "idle";
    }
}
