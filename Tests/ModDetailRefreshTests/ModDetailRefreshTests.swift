import Foundation
import Testing
@testable import StarHubTHCore

/// La composition des deux appels réseau de la fiche (description, puis
/// changelogs complets). Le réseau est stubbé : ce qui se teste, c'est la
/// règle — une description vide invalide le tout, un changelog vide est
/// acceptable.
@Suite struct ModDetailRefreshTests {

    @Test func composesDescriptionAndChangelog() {
        var raw: ModDetailRaw?
        ModDetailRefresh.fetch(
            modId: 42,
            fetchDescription: { _, done in done("desc") },
            fetchChangelogs: { _, done in done("log") },
            completion: { raw = $0 })
        #expect(raw?.description == "desc")
        #expect(raw?.changelog == "log")
    }

    /// Une description vide (pas de clé, hors-ligne, mod inconnu) invalide
    /// le tout — le repli cache/local de l'appelant reste intact. Le
    /// changelog n'est alors jamais demandé.
    @Test func emptyDescriptionVoidsTheRefresh() {
        var raw: ModDetailRaw?
        var changelogAsked = false
        ModDetailRefresh.fetch(
            modId: 42,
            fetchDescription: { _, done in done("") },
            fetchChangelogs: { _, done in changelogAsked = true; done("log") },
            completion: { raw = $0 })
        #expect(raw == nil)
        #expect(!changelogAsked)
    }

    /// Un mod sans changelog : la description seule suffit.
    @Test func emptyChangelogIsFine() {
        var raw: ModDetailRaw?
        ModDetailRefresh.fetch(
            modId: 42,
            fetchDescription: { _, done in done("desc") },
            fetchChangelogs: { _, done in done("") },
            completion: { raw = $0 })
        #expect(raw?.description == "desc")
        #expect(raw?.changelog == "")
    }

    // MARK: - A3-T7 — repli v2

    /// v1 réussit : le repli n'est jamais appelé.
    @Test func fallbackIsNotAskedWhenV1Succeeds() {
        var fallbackAsked = false
        var raw: ModDetailRaw?
        ModDetailRefresh.fetch(
            modId: 42,
            fetchDescription: { _, done in done("desc") },
            fetchChangelogs: { _, done in done("log") },
            fallback: { _, done in fallbackAsked = true; done(nil) },
            completion: { raw = $0 })
        #expect(!fallbackAsked)
        #expect(raw?.description == "desc")
    }

    /// v1 vide (pas de clé, quota) : la v2 rend les deux, le changelog v1
    /// n'est pas demandé.
    @Test func emptyV1DescriptionFallsBackToV2() {
        var changelogAsked = false
        var raw: ModDetailRaw?
        ModDetailRefresh.fetch(
            modId: 42,
            fetchDescription: { _, done in done("") },
            fetchChangelogs: { _, done in changelogAsked = true; done("log") },
            fallback: { id, done in done(ModDetailRaw(description: "v2 \(id)", changelog: "v2 log")) },
            completion: { raw = $0 })
        #expect(raw?.description == "v2 42")
        #expect(raw?.changelog == "v2 log")
        #expect(!changelogAsked)
    }

    /// Les deux échouent : `nil`, le repli local de l'appelant reste.
    @Test func bothFailingKeepsNil() {
        var raw: ModDetailRaw? = ModDetailRaw(description: "x", changelog: "")
        ModDetailRefresh.fetch(
            modId: 42,
            fetchDescription: { _, done in done("") },
            fetchChangelogs: { _, done in done("log") },
            fallback: { _, done in done(nil) },
            completion: { raw = $0 })
        #expect(raw == nil)
    }
}
