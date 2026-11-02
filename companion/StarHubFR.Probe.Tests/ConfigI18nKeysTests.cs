using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text.Json;
using StarHubFR.Probe;
using Xunit;

namespace StarHubFR.Probe.Tests;

/// <summary>L'éditeur de config de StarHubFR rapproche `config.&lt;champ&gt;.name`
/// d'i18n du champ de `config.json` par son nom, sans la casse
/// (`ConfigLabelResolver`). Des clés `config.harmony` ne rejoignaient aucun
/// champ : l'éditeur montrait `MeasureHarmonyPatches` brut, sans aide.</summary>
public class ConfigI18nKeysTests
{
    private static string I18n([CallerFilePath] string here = "") =>
        Path.Combine(Path.GetDirectoryName(here)!, "..", "StarHubFR.Probe", "i18n");

    [Theory]
    [InlineData("default.json")]
    [InlineData("fr.json")]
    public void EveryConfigFieldHasANameAndATooltip(string file)
    {
        var keys = JsonSerializer.Deserialize<Dictionary<string, string>>(
            File.ReadAllText(Path.Combine(I18n(), file)))!
            .Keys.Select(k => k.ToLowerInvariant()).ToHashSet();
        foreach (var field in typeof(ModConfig).GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            string stem = "config." + field.Name.ToLowerInvariant();
            Assert.Contains(stem + ".name", keys);
            Assert.Contains(stem + ".tooltip", keys);
        }
    }
}
