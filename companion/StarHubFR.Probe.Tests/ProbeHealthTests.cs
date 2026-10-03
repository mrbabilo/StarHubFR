// companion/StarHubFR.Probe.Tests/ProbeHealthTests.cs
using StarHubFR.Probe;
using Xunit;

public class ProbeHealthTests
{
    // — PackSeam (X119) —

    [Fact]
    public void ProfilerInstalledWins() =>
        Assert.Equal("profiler", ProbeHealth.PackSeam(profiler: true, contentPatcherLoaded: true, seamPatched: false, sectionsSeen: false));

    /// Content Patcher en pause : « absent », pas la régression.
    [Fact]
    public void ContentPatcherAbsentIsNotAMissingSeam() =>
        Assert.Equal("absent", ProbeHealth.PackSeam(profiler: false, contentPatcherLoaded: false, seamPatched: false, sectionsSeen: false));

    /// Content Patcher là, couture introuvable : la seule vraie « missing ».
    [Fact]
    public void ContentPatcherPresentWithoutSeamIsMissing() =>
        Assert.Equal("missing", ProbeHealth.PackSeam(profiler: false, contentPatcherLoaded: true, seamPatched: false, sectionsSeen: false));

    /// Session sans chargement de pack : posée mais rien vu.
    [Fact]
    public void ArmedSeamWithoutSectionsIsIdle() =>
        Assert.Equal("idle", ProbeHealth.PackSeam(profiler: false, contentPatcherLoaded: true, seamPatched: true, sectionsSeen: false));

    [Fact]
    public void SeenSectionsAreOk() =>
        Assert.Equal("ok", ProbeHealth.PackSeam(profiler: false, contentPatcherLoaded: true, seamPatched: true, sectionsSeen: true));

    // — AssetHook (X119) —

    [Fact]
    public void UnarmedHookIsMissing() =>
        Assert.Equal("missing", ProbeHealth.AssetHook(hookPatched: false, callsSeen: 0));

    /// Accroche posée, aucun rappel vu : rien à observer, pas un SMAPI non couvert.
    [Fact]
    public void ArmedHookWithoutCallsIsIdle() =>
        Assert.Equal("idle", ProbeHealth.AssetHook(hookPatched: true, callsSeen: 0));

    [Fact]
    public void SeenCallsAreOk() =>
        Assert.Equal("ok", ProbeHealth.AssetHook(hookPatched: true, callsSeen: 12));
}
