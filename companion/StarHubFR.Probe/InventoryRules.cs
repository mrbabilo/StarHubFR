using System;

namespace StarHubFR.Probe;

/// <summary>Ce qu'un relevé a vu d'un `config.json`.</summary>
internal enum ReadKind { Absent, Error, Present }

/// <summary>
/// `Stamp` : la date du fichier (Present), ou celle de son dossier (Absent :
/// quand la suppression a eu lieu). Toujours en UTC.
/// </summary>
internal readonly record struct Observation(ReadKind Kind, DateTime? Stamp = null, string? Sha = null);

/// <summary>
/// Les règles de l'inventaire, sans SMAPI ni disque : testables à part.
/// </summary>
internal static class InventoryRules
{
    /// <summary>
    /// Applique une observation à l'état retenu d'un `config.json`. Rend vrai
    /// si l'empreinte a changé : une ligne `configChanged` à émettre.
    ///
    /// Une erreur de lecture n'est pas une absence : elle ne change rien de ce
    /// qu'on sait, elle oublie seulement la date pour relire à la minute
    /// suivante. La traiter comme une absence coupait deux fois la session
    /// pour un réglage qui n'avait pas bougé.
    /// </summary>
    public static bool Apply(ref DateTime? stamp, ref string? sha, Observation seen)
    {
        switch (seen.Kind)
        {
            case ReadKind.Error:
                stamp = null;
                return false;
            case ReadKind.Absent:
                stamp = null;
                if (sha is null) return false;
                sha = null;
                return true;
            default:
                stamp = seen.Stamp;
                if (seen.Sha == sha) return false;
                sha = seen.Sha;
                return true;
        }
    }

    /// <summary>
    /// Quand le réglage a changé, borné par ce qu'on sait : pas avant le
    /// relevé précédent (une copie garde la date de l'original, une config
    /// restaurée daterait sinon de sa sauvegarde), pas après maintenant
    /// (horloge d'un disque décalée).
    /// </summary>
    public static DateTime ChangedAt(DateTime? fileStampUtc, DateTime notBeforeUtc, DateTime atUtc)
    {
        if (fileStampUtc is not { } stamp) return atUtc;
        if (stamp < notBeforeUtc) return notBeforeUtc;
        return stamp > atUtc ? atUtc : stamp;
    }
}
