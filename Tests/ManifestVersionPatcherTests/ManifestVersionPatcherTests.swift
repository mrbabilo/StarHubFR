import Testing
import Foundation
@testable import StarHubTHCore

private func semverNewer(_ a: String, _ b: String) -> Bool {
    // Simple stub for tests: dotted numeric compare, a > b.
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x > y }
    }
    return false
}

struct ManifestVersionPatcherTests {
    // ── decide ───────────────────────────────────────────────────
    @Test func correctsVersionWhenNexusHigher() {
        let d = ManifestVersionPatcher.decide(
            nexusVersion: "1.2.0", nexusUploaded: nil,
            manifestVersion: "1.1.0", manifestModified: nil, isNewer: semverNewer)
        #expect(d == .correctVersion(to: "1.2.0"))
    }

    @Test func neverDowngrade() {
        let d = ManifestVersionPatcher.decide(
            nexusVersion: "1.1.0", nexusUploaded: nil,
            manifestVersion: "1.2.0", manifestModified: nil, isNewer: semverNewer)
        #expect(d == .noChange)
    }

    @Test func equalVersionNewerUploadRefreshesDate() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let d = ManifestVersionPatcher.decide(
            nexusVersion: "1.2.0", nexusUploaded: newer,
            manifestVersion: "1.2.0", manifestModified: older, isNewer: semverNewer)
        #expect(d == .refreshDate)
    }

    @Test func equalVersionNoNewerUploadNoChange() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let d = ManifestVersionPatcher.decide(
            nexusVersion: "1.2.0", nexusUploaded: older,
            manifestVersion: "1.2.0", manifestModified: newer, isNewer: semverNewer)
        #expect(d == .noChange)
    }

    @Test func missingVersionNewerUploadRefreshesDate() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let d = ManifestVersionPatcher.decide(
            nexusVersion: "1.2.0", nexusUploaded: newer,
            manifestVersion: nil, manifestModified: older, isNewer: semverNewer)
        #expect(d == .refreshDate)
    }

    @Test func missingVersionNoDateEvidenceNoChange() {
        let d = ManifestVersionPatcher.decide(
            nexusVersion: "1.2.0", nexusUploaded: nil,
            manifestVersion: nil, manifestModified: nil, isNewer: semverNewer)
        #expect(d == .noChange)
    }

    // ── extractVersionValue ──────────────────────────────────────
    @Test func extractsStringVersion() {
        let raw = "{\n  \"Name\": \"X\",\n  \"Version\": \"1.2.3\",\n  \"UniqueID\": \"a.b\"\n}"
        #expect(ManifestVersionPatcher.extractVersionValue(from: raw) == "1.2.3")
    }

    @Test func extractReturnsNilForDictVersionForm() {
        let raw = "{ \"Version\": { \"MajorVersion\": 1, \"MinorVersion\": 2 } }"
        #expect(ManifestVersionPatcher.extractVersionValue(from: raw) == nil)
    }

    @Test func extractReturnsNilWhenAbsent() {
        #expect(ManifestVersionPatcher.extractVersionValue(from: "{ \"Name\": \"X\" }") == nil)
    }

    // ── replaceVersionValue ──────────────────────────────────────
    @Test func replacesOnlyTheVersionValuePreservingRest() {
        let raw = "{\n  // author comment\n  \"Name\": \"X\",\n  \"Version\": \"1.1.0\",\n  \"UniqueID\": \"a.b\"\n}"
        let out = ManifestVersionPatcher.replaceVersionValue(in: raw, with: "1.2.0")
        #expect(out == "{\n  // author comment\n  \"Name\": \"X\",\n  \"Version\": \"1.2.0\",\n  \"UniqueID\": \"a.b\"\n}")
    }

    @Test func replaceReturnsNilForDictForm() {
        let raw = "{ \"Version\": { \"MajorVersion\": 1 } }"
        #expect(ManifestVersionPatcher.replaceVersionValue(in: raw, with: "1.2.0") == nil)
    }

    @Test func replaceIsCaseInsensitiveOnKey() {
        let raw = "{ \"version\": \"1.0.0\" }"
        #expect(ManifestVersionPatcher.replaceVersionValue(in: raw, with: "2.0.0") == "{ \"version\": \"2.0.0\" }")
    }

    @Test func replaceMatchesUppercaseKey() {
        let raw = "{ \"VERSION\": \"1.0.0\" }"
        #expect(ManifestVersionPatcher.replaceVersionValue(in: raw, with: "2.0.0") == "{ \"VERSION\": \"2.0.0\" }")
    }

    @Test func replaceEscapesDollarInNewVersion() {
        let raw = "{ \"Version\": \"1.0.0\" }"
        // A '$' must be treated literally, not as a regex template backreference.
        #expect(ManifestVersionPatcher.replaceVersionValue(in: raw, with: "1.0.0$2") == "{ \"Version\": \"1.0.0$2\" }")
    }

    @Test func emptyNexusVersionIsNoChange() {
        let d = ManifestVersionPatcher.decide(
            nexusVersion: "", nexusUploaded: Date(timeIntervalSince1970: 2_000),
            manifestVersion: "1.0.0", manifestModified: Date(timeIntervalSince1970: 1_000),
            isNewer: semverNewer)
        #expect(d == .noChange)
    }

    @Test func emptyStringManifestVersionFallsThroughToDate() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let d = ManifestVersionPatcher.decide(
            nexusVersion: "1.2.0", nexusUploaded: newer,
            manifestVersion: "", manifestModified: older, isNewer: semverNewer)
        #expect(d == .refreshDate)
    }
}
