import Testing
import Foundation
@testable import StarHubTHCore

/// « Signaler un bug » ouvre le formulaire `bug_app.yml` du dépôt, la
/// version de l'app et celle de macOS déjà remplies.
struct BugReportLinkTests {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    @Test func opensTheAppBugFormWithVersionsFilled() {
        let url = BugReportLink.url(appVersion: "1.71.1", build: "98",
                                    macOS: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1),
                                    appleSilicon: true)
        #expect(url.absoluteString.hasPrefix("https://github.com/mrbabilo/StarHubFR/issues/new?"))
        let q = query(url)
        #expect(q["template"] == "bug_app.yml")
        #expect(q["starhubfr-version"] == "v1.71.1 (build 98)")
        #expect(q["macos-version"] == "macOS 26.0.1 · Apple Silicon")
        #expect(q["labels"] == "bug")
    }

    @Test func aMissingPatchAndIntelReadCleanly() {
        let url = BugReportLink.url(appVersion: "1.71.1", build: nil,
                                    macOS: OperatingSystemVersion(majorVersion: 15, minorVersion: 5, patchVersion: 0),
                                    appleSilicon: false)
        let q = query(url)
        #expect(q["starhubfr-version"] == "v1.71.1")
        #expect(q["macos-version"] == "macOS 15.5 · Intel")
        #expect(!url.absoluteString.contains(" "))
    }
}
