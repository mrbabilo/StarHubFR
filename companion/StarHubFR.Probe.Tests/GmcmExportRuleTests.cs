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

    // C4-T18 : une classe ne s'instancie que si ses membres sont ceux du
    // `config.json`, pour ne jamais lancer le constructeur d'autre chose.
    [Fact]
    public void AClassWithTheKeysOfTheConfigCoversIt() =>
        Assert.True(GmcmExportRule.CoversConfig(new[] { "Enabled", "Speed", "Extra" },
                                                "{\"enabled\": true, \"Speed\": 2}"));

    [Fact]
    public void AClassMissingTooManyKeysDoesNotCoverTheConfig() =>
        Assert.False(GmcmExportRule.CoversConfig(new[] { "Enabled" },
                                                 "{\"Enabled\": true, \"Speed\": 2, \"Size\": 3}"));

    [Theory]
    [InlineData(null)]
    [InlineData("{}")]
    [InlineData("[1]")]
    [InlineData("not json")]
    public void WithoutAReadableConfigNothingIsCovered(string? snapshot) =>
        Assert.False(GmcmExportRule.CoversConfig(new[] { "Enabled" }, snapshot));

    // `KeybindSetting.Get` n'existe que pour le premier bouton de la liste :
    // lu à sa place, « F5, LeftStick » sortait en « F5 » et ne concordait plus
    // avec `config.json`.
    [Theory]
    [InlineData("ToggleSetting", "Get")]
    [InlineData("TextboxSetting", "Get")]
    [InlineData("SliderSetting", "Get")]
    [InlineData("DropdownSetting", "Get")]
    [InlineData("KeybindSetting", "GetKeybindList")]
    [InlineData("ColorPickerSetting", "Getter")]
    public void McmSettingsReadTheirValueThroughTheirOwnGetter(string setting, string getter) =>
        Assert.Equal(getter, GmcmExportRule.McmGetter(setting));
}
