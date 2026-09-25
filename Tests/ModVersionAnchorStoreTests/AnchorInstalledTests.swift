import Testing
import Foundation
@testable import StarHubTHCore

/// Ancrage à l'installation. Dossiers temporaires, `UserDefaults` dédié.
struct AnchorInstalledTests {

    private func freshStore() -> ModVersionAnchorStore {
        let name = UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return ModVersionAnchorStore(defaults: d)
    }

    /// Un dossier de mod ; `manifest: nil` le laisse sans manifest.
    private func modFolder(_ manifest: String?) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnchorInstalled-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let manifest {
            try! Data(manifest.utf8).write(to: dir.appendingPathComponent("manifest.json"))
        }
        return dir.path
    }

    private let facts = NexusInstallFacts(modId: "123", fileId: 456,
                                          fileUploadedAt: Date(timeIntervalSince1970: 1_000))

    @Test func anInstalledFolderGetsAnInstallAnchorAndIsReported() {
        let store = freshStore()
        let path = modFolder(#"{"Name":"A","UniqueID":"me.a","Version":"1.2.3"}"#)
        let now = Date(timeIntervalSince1970: 42)

        #expect(store.anchorInstalled(folderPaths: [path], now: now) == ["me.a"])
        let anchor = store.anchor(for: "me.a")
        #expect(anchor?.anchoredVersion == "1.2.3")
        #expect(anchor?.origin == .install)
        #expect(anchor?.anchoredAt == now)
    }

    @Test func unreadableManifestsAreSkippedAndNotReported() {
        // Sans manifest, sans UniqueID, UniqueID vide, sans version.
        let store = freshStore()
        let paths = [
            modFolder(nil),
            modFolder(#"{"Name":"B","Version":"1.0"}"#),
            modFolder(#"{"Name":"C","UniqueID":"","Version":"1.0"}"#),
            modFolder(#"{"Name":"D","UniqueID":"me.d"}"#),
        ]
        #expect(store.anchorInstalled(folderPaths: paths).isEmpty)
        #expect(store.all().isEmpty)
    }

    @Test func theObjectFormOfVersionIsAnchored() {
        let store = freshStore()
        let path = modFolder(#"{"UniqueID":"me.o","Version":{"MajorVersion":2,"MinorVersion":5}}"#)
        #expect(store.anchorInstalled(folderPaths: [path]) == ["me.o"])
        #expect(store.anchor(for: "me.o")?.anchoredVersion == "2.5.0")
    }

    @Test func uniqueIdKeyIsReadCaseInsensitively() {
        let store = freshStore()
        let path = modFolder(#"{"uniqueid":"me.c","version":"3.0"}"#)
        #expect(store.anchorInstalled(folderPaths: [path]) == ["me.c"])
    }

    @Test func factsAreKeptForASingleFolder() {
        let store = freshStore()
        let path = modFolder(#"{"UniqueID":"me.s","Version":"1.0"}"#)
        store.anchorInstalled(folderPaths: [path], nexusFacts: facts)
        #expect(store.anchor(for: "me.s")?.nexusFacts == facts)
    }

    @Test func factsAreDroppedForAPackOfSeveralFolders() {
        let store = freshStore()
        let paths = [modFolder(#"{"UniqueID":"me.p1","Version":"1.0"}"#),
                     modFolder(#"{"UniqueID":"me.p2","Version":"1.0"}"#)]
        #expect(store.anchorInstalled(folderPaths: paths, nexusFacts: facts) == ["me.p1", "me.p2"])
        #expect(store.anchor(for: "me.p1")?.nexusFacts == nil)
        #expect(store.anchor(for: "me.p2")?.nexusFacts == nil)
    }

    @Test func aReinstallWithoutFactsKeepsTheEarlierOnes() {
        // Restauration de backup : garde les faits d'avant.
        let store = freshStore()
        let path = modFolder(#"{"UniqueID":"me.r","Version":"1.0"}"#)
        store.anchorInstalled(folderPaths: [path], nexusFacts: facts)
        store.anchorInstalled(folderPaths: [path])
        #expect(store.anchor(for: "me.r")?.nexusFacts == facts)
    }
}
