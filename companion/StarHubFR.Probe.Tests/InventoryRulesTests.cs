// companion/StarHubFR.Probe.Tests/InventoryRulesTests.cs
using StarHubFR.Probe;
using Xunit;

public class InventoryRulesTests
{
    private static readonly DateTime Monday = new(2026, 11, 2, 10, 0, 0, DateTimeKind.Utc);
    private static readonly DateTime Tuesday = Monday.AddDays(1);
    private static readonly DateTime Wednesday = Monday.AddDays(2);

    // — Apply —

    [Fact]
    public void ANewFingerprintIsAChange()
    {
        DateTime? stamp = Monday;
        string? sha = "a";
        Assert.True(InventoryRules.Apply(ref stamp, ref sha, new Observation(ReadKind.Present, Tuesday, "b")));
        Assert.Equal(Tuesday, stamp);
        Assert.Equal("b", sha);
    }

    /// Fichier réécrit à l'identique : sa date avance, le réglage n'a pas bougé.
    [Fact]
    public void ANewDateAloneIsNotAChange()
    {
        DateTime? stamp = Monday;
        string? sha = "a";
        Assert.False(InventoryRules.Apply(ref stamp, ref sha, new Observation(ReadKind.Present, Tuesday, "a")));
        Assert.Equal(Tuesday, stamp);
        Assert.Equal("a", sha);
    }

    /// L'erreur oublie la date pour relire à la minute suivante, et garde
    /// l'empreinte : le fichier relu intact ne coupe pas la session.
    [Fact]
    public void AReadErrorChangesNothingAndTheNextReadStaysQuiet()
    {
        DateTime? stamp = Monday;
        string? sha = "a";
        Assert.False(InventoryRules.Apply(ref stamp, ref sha, new Observation(ReadKind.Error)));
        Assert.Null(stamp);
        Assert.Equal("a", sha);
        Assert.False(InventoryRules.Apply(ref stamp, ref sha, new Observation(ReadKind.Present, Monday, "a")));
        Assert.Equal(Monday, stamp);
    }

    [Fact]
    public void ADeletedFileIsAChange()
    {
        DateTime? stamp = Monday;
        string? sha = "a";
        Assert.True(InventoryRules.Apply(ref stamp, ref sha, new Observation(ReadKind.Absent, Tuesday)));
        Assert.Null(stamp);
        Assert.Null(sha);
    }

    [Fact]
    public void AFileThatNeverExistedIsNotAChange()
    {
        DateTime? stamp = null;
        string? sha = null;
        Assert.False(InventoryRules.Apply(ref stamp, ref sha, new Observation(ReadKind.Absent, Tuesday)));
        Assert.Null(stamp);
        Assert.Null(sha);
    }

    /// Supprimé puis restauré à l'identique : deux changements, la session a
    /// bien tourné un temps sans ce réglage.
    [Fact]
    public void ADeletedFileRestoredUnchangedIsAChangeAgain()
    {
        DateTime? stamp = Monday;
        string? sha = "a";
        Assert.True(InventoryRules.Apply(ref stamp, ref sha, new Observation(ReadKind.Absent, Tuesday)));
        Assert.True(InventoryRules.Apply(ref stamp, ref sha, new Observation(ReadKind.Present, Wednesday, "a")));
        Assert.Equal(Wednesday, stamp);
        Assert.Equal("a", sha);
    }

    // — ChangedAt —

    [Fact]
    public void WithoutAFileDateTheChangeIsDatedNow() =>
        Assert.Equal(Wednesday, InventoryRules.ChangedAt(null, Monday, Wednesday));

    [Fact]
    public void ADateInsideTheBoundsIsKept() =>
        Assert.Equal(Tuesday, InventoryRules.ChangedAt(Tuesday, Monday, Wednesday));

    /// Une config restaurée garde la date de sa sauvegarde.
    [Fact]
    public void ADateBeforeThePreviousSurveyIsRaisedToIt() =>
        Assert.Equal(Tuesday, InventoryRules.ChangedAt(Monday, Tuesday, Wednesday));

    /// Horloge d'un disque décalée.
    [Fact]
    public void ADateInTheFutureIsBroughtBackToNow() =>
        Assert.Equal(Tuesday, InventoryRules.ChangedAt(Wednesday, Monday, Tuesday));
}
