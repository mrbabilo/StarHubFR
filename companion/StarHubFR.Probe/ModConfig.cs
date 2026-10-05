namespace StarHubFR.Probe;

/// <summary>`config.json` de la sonde, créé au premier lancement. Public :
/// le miroir de remise à défaut est testé (`ModConfigMirrorTests`).</summary>
public sealed class ModConfig
{
    /// <summary>
    /// D4-T5 : chronométrer chaque méthode de patch Harmony des autres mods.
    /// Désactivé par défaut : l'enveloppe ajoute un prefix et un finalizer à
    /// chaque patch, dont certains tirent des milliers de fois par trame — le
    /// coût d'observation se mesure en comparant deux sessions, avec et sans.
    /// </summary>
    public bool MeasureHarmonyPatches { get; set; } = false;

    /// <summary>
    /// D4-T6a : relever la mémoire des textures résidentes, par attributaire.
    /// Suivi par événements SMAPI, sans patch — mais le relevé passe par un
    /// accès au cache à chaque asset chargé : désactivé par défaut, le coût
    /// d'observation se mesure en comparant deux sessions, avec et sans.
    /// </summary>
    public bool MeasureTextures { get; set; } = false;

    /// <summary>La remise à défaut du menu de configuration : **tous** les
    /// champs connus passent par ici — un champ ajouté à la classe sans
    /// passer par ce miroir resterait au réglage courant quand l'utilisateur
    /// clique « Réinitialiser » (testé : `ModConfigMirrorTests`).</summary>
    public void Apply(ModConfig defaults)
    {
        MeasureHarmonyPatches = defaults.MeasureHarmonyPatches;
        MeasureTextures = defaults.MeasureTextures;
    }
}
