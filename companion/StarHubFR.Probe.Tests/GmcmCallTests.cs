using System;
using StarHubFR.Probe;
using Xunit;

namespace StarHubFR.Probe.Tests;

/// <summary>La sonde parle à GMCM par réflexion : ces signatures recopient
/// celles de `GenericModConfigMenu.Framework.Api` (1.16.0). Deux paramètres
/// optionnels y dépassent ce que la sonde renseigne.</summary>
public class GmcmCallTests
{
    private sealed class FakeApi
    {
        public bool? TitleScreenOnly;
        public string? FieldId = "non appelé";

        public void Register(object? mod, Action reset, Action save, bool titleScreenOnly = true) =>
            TitleScreenOnly = titleScreenOnly;

        public void AddBoolOption(object? mod, Func<bool> getValue, Action<bool> setValue,
            Func<string> name, Func<string>? tooltip = null, string? fieldId = null) =>
            FieldId = fieldId;

        public void AddKeybind(object? mod, Func<bool> getValue) { }
        public void AddKeybind(object? mod, Func<bool> getValue, Action<bool> setValue, string name) { }
    }

    [Fact]
    public void Find_accepts_trailing_optional_parameters()
    {
        Assert.NotNull(GmcmCall.Find(typeof(FakeApi), "AddBoolOption", 5));
        Assert.NotNull(GmcmCall.Find(typeof(FakeApi), "Register", 4));
    }

    [Fact]
    public void Find_refuses_a_call_the_signature_cannot_take()
    {
        Assert.Null(GmcmCall.Find(typeof(FakeApi), "Register", 5));
        Assert.Null(GmcmCall.Find(typeof(FakeApi), "AddBoolOption", 2));
        Assert.Null(GmcmCall.Find(typeof(FakeApi), "Absent", 1));
    }

    [Fact]
    public void Find_picks_the_overload_that_fits()
    {
        Assert.Equal(4, GmcmCall.Find(typeof(FakeApi), "AddKeybind", 4)!.GetParameters().Length);
    }

    [Fact]
    public void Invoke_fills_the_remaining_parameters_with_their_defaults()
    {
        var api = new FakeApi();
        var method = GmcmCall.Find(typeof(FakeApi), "AddBoolOption", 5)!;

        GmcmCall.Invoke(method, api, new object?[]
        {
            null,
            (Func<bool>)(() => true),
            (Action<bool>)(_ => { }),
            (Func<string>)(() => "nom"),
            (Func<string>?)(() => "aide"),
        });

        Assert.Null(api.FieldId);
    }

    [Fact]
    public void Invoke_keeps_a_value_given_for_an_optional_parameter()
    {
        var api = new FakeApi();
        var method = GmcmCall.Find(typeof(FakeApi), "Register", 4)!;

        GmcmCall.Invoke(method, api, new object?[] { null, (Action)(() => { }), (Action)(() => { }), false });

        Assert.False(api.TitleScreenOnly);
    }
}
