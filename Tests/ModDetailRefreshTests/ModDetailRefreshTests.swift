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
}
