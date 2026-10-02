import Testing
@testable import StarHubTHCore

@Suite struct ChangelogExcerptTests {
    private let preamble = "# Changelog\n\nAll notable changes…\n\n"

    @Test("Garde les deux dernières versions, sans préambule")
    func keepsTwoLatestVersions() {
        let md = preamble + "## [1.3.0] - 2026-09-03\n\n- C\n\n## [1.2.0] - 2026-09-02\n\n- B\n\n## [1.1.0] - 2026-09-01\n\n- A\n"
        #expect(ChangelogExcerpt.latest(md)
            == "## [1.3.0] - 2026-09-03\n\n- C\n\n## [1.2.0] - 2026-09-02\n\n- B")
    }

    @Test("Un [Unreleased] vide est sauté")
    func skipsEmptyUnreleased() {
        let md = preamble + "## [Unreleased]\n\n## [1.2.0]\n\n- B\n\n## [1.1.0]\n\n- A\n\n## [1.0.0]\n\n- Z\n"
        #expect(ChangelogExcerpt.latest(md) == "## [1.2.0]\n\n- B\n\n## [1.1.0]\n\n- A")
    }

    @Test("Un [Unreleased] rempli compte comme la dernière section")
    func filledUnreleasedCounts() {
        let md = preamble + "## [Unreleased]\n\n### Added\n\n- N\n\n## [1.2.0]\n\n- B\n\n## [1.1.0]\n\n- A\n"
        #expect(ChangelogExcerpt.latest(md)
            == "## [Unreleased]\n\n### Added\n\n- N\n\n## [1.2.0]\n\n- B")
    }

    @Test("Les sous-titres ### restent dans leur version")
    func subheadingsStayInSection() {
        let md = "## [1.1.0]\n### Fixed\n- A\n## [1.0.0]\n- Z\n"
        #expect(ChangelogExcerpt.latest(md, count: 1) == "## [1.1.0]\n### Fixed\n- A")
    }

    @Test("Une carte par version : titre, date, groupes, entrées prolongées")
    func structuresReleases() {
        let md = preamble + "## [Unreleased]\n\n## [1.2.0] - 2026-09-02\n\n### Added\n\n- **A.** un\n  suite\n- B\n\n### Fixed\n\n- C\n\n## [1.1.0] - 2026-09-01\n\n- D\n"
        let releases = ChangelogExcerpt.releases(md)
        #expect(releases.map(\.version) == ["1.2.0", "1.1.0"])
        #expect(releases.first?.date == "2026-09-02")
        #expect(releases.first?.groups == [
            .init(kind: .added, entries: ["**A.** un suite", "B"]),
            .init(kind: .fixed, entries: ["C"])])
        // Sans sous-titre : un groupe « autre », pas une entrée perdue.
        #expect(releases.last?.groups == [.init(kind: .other, entries: ["D"])])
    }

    @Test("Un [Unreleased] rempli devient une version sans date")
    func unreleasedHasNoDate() {
        let md = "## [Unreleased]\n### Changed\n- N\n## [1.0.0]\n- Z\n"
        let first = ChangelogExcerpt.releases(md).first
        #expect(first?.isUnreleased == true)
        #expect(first?.date == nil)
        #expect(first?.groups == [.init(kind: .changed, entries: ["N"])])
    }
}
