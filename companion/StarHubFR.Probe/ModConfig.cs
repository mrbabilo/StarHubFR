namespace StarHubFR.Probe;

/// <summary>`config.json` de la sonde, créé au premier lancement.</summary>
internal sealed class ModConfig
{
    /// <summary>
    /// D4-T5 : chronométrer chaque méthode de patch Harmony des autres mods.
    /// Désactivé par défaut : l'enveloppe ajoute un prefix et un finalizer à
    /// chaque patch, dont certains tirent des milliers de fois par trame — le
    /// coût d'observation se mesure en comparant deux sessions, avec et sans.
    /// </summary>
    public bool MeasureHarmonyPatches { get; set; } = false;
}
