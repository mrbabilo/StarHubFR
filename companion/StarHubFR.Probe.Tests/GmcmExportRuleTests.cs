// companion/StarHubFR.Probe.Tests/GmcmExportRuleTests.cs
using StarHubFR.Probe;
using Xunit;

public class GmcmExportRuleTests
{
    [Fact]
    public void FirstWriteOfTheSessionHappens() =>
        Assert.True(GmcmExportRule.ShouldWrite(exportedMods: null, exportedLanguage: null, registryMods: 167, language: "fr", force: false));

    /// Même registre, même langue : les 4,4 Mo ne se réécrivent pas à chaque chargement.
    [Fact]
    public void SameRegistryAndLanguageIsSkipped() =>
        Assert.False(GmcmExportRule.ShouldWrite(exportedMods: 167, exportedLanguage: "fr", registryMods: 167, language: "fr", force: false));

    [Fact]
    public void AChangedRegistryRewrites() =>
        Assert.True(GmcmExportRule.ShouldWrite(exportedMods: 167, exportedLanguage: "fr", registryMods: 166, language: "fr", force: false));

    [Fact]
    public void AChangedLanguageRewrites() =>
        Assert.True(GmcmExportRule.ShouldWrite(exportedMods: 167, exportedLanguage: "fr", registryMods: 167, language: "en", force: false));

    /// La commande console demande une réécriture explicite.
    [Fact]
    public void ForceAlwaysRewrites() =>
        Assert.True(GmcmExportRule.ShouldWrite(exportedMods: 167, exportedLanguage: "fr", registryMods: 167, language: "fr", force: true));

    /// MCM (ModernConfigMenu) : ses réglages prennent le genre d'option GMCM
    /// que l'app sait lire ; titres, boutons, images et liens ne se règlent pas.
    [Theory]
    [InlineData("ToggleSetting", "SimpleModOption")]
    [InlineData("TextboxSetting", "SimpleModOption")]
    [InlineData("KeybindSetting", "SimpleModOption")]
    [InlineData("SliderSetting", "NumericModOption")]
    [InlineData("DropdownSetting", "ChoiceModOption")]
    public void McmSettingsMapToGmcmKinds(string setting, string kind) =>
        Assert.Equal(kind, GmcmExportRule.McmKind(setting));

    [Theory]
    [InlineData("LabelSetting")]
    [InlineData("ButtonSetting")]
    [InlineData("PageLinkSetting")]
    [InlineData("ImageSetting")]
    [InlineData("ComplexSetting")]
    public void McmDisplayOnlySettingsAreSkipped(string setting) =>
        Assert.Null(GmcmExportRule.McmKind(setting));
}
