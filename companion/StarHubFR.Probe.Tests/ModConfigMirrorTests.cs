using StarHubFR.Probe;
using Xunit;

namespace StarHubFR.Probe.Tests;

/// <summary>D4-T6 bis — la remise à défaut du menu de configuration passe
/// par **tous** les champs : un champ ajouté à `ModConfig` sans passer par
/// `Apply` resterait au réglage courant quand l'utilisateur réinitialise.</summary>
public class ModConfigMirrorTests
{
    [Fact]
    public void ApplyResetsEveryKnownOption()
    {
        var config = new ModConfig { MeasureHarmonyPatches = true, MeasureTextures = true };
        config.Apply(new ModConfig());
        Assert.False(config.MeasureHarmonyPatches);
        Assert.False(config.MeasureTextures);
    }

    [Fact]
    public void ApplyKeepsOnlyTheDefaultsOfTheSource()
    {
        var defaults = new ModConfig { MeasureTextures = true };
        var config = new ModConfig { MeasureHarmonyPatches = true, MeasureTextures = true };
        config.Apply(defaults);
        Assert.False(config.MeasureHarmonyPatches);   // défaut de la classe
        Assert.True(config.MeasureTextures);          // défaut de la source
    }
}
