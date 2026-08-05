import Testing
@testable import StarHubTHCore

/// Garde zip-slip : refuser une archive dont une entry sortirait de destDir
/// (`../` ou chemin absolu). `unzip` (Info-ZIP) extrait ces entries hors du
/// dossier cible. Audit 2026-08-05, `ModZipInstaller.extractArchive`.
@Suite struct ZipSlipTests {

    // MARK: containsTraversalPath

    @Test func plainEntriesAreSafe() {
        #expect(!ModZipInstaller.containsTraversalPath(["manifest.json", "assets/foo.png", "i18n/default.json"]))
    }

    @Test func parentDirectoryIsRejected() {
        #expect(ModZipInstaller.containsTraversalPath(["../etc/passwd"]))
        #expect(ModZipInstaller.containsTraversalPath(["ok.txt", "../../secret"]))
    }

    @Test func mixedTraversalMidPathIsRejected() {
        // `a/../../b` remonte au-dessus de la racine.
        #expect(ModZipInstaller.containsTraversalPath(["a/../../b"]))
    }

    @Test func absolutePathIsRejected() {
        #expect(ModZipInstaller.containsTraversalPath(["/etc/passwd"]))
    }

    @Test func dotPrefixThatIsNotParentIsSafe() {
        // `.hidden` et `..foo` (nom commençant par ..) ne sont pas une composante `..`.
        #expect(!ModZipInstaller.containsTraversalPath([".hidden", "..foo/bar"]))
    }

    @Test func emptyListIsSafe() {
        #expect(!ModZipInstaller.containsTraversalPath([]))
    }

    // MARK: pathNamesFromSevenZipListing

    @Test func sevenZipListingParsesPathEntries() {
        let listing = """
        7-Zip
        Path = manifest.json
        Folder = -
        Size = 100
        Path = assets/foo.png
        Size = 2048
        """
        #expect(ModZipInstaller.pathNamesFromSevenZipListing(listing) == ["manifest.json", "assets/foo.png"])
    }

    @Test func sevenZipListingDetectsTraversalAmongParsedPaths() {
        let listing = """
        Path = ok.txt
        Path = ../../../etc/shadow
        """
        let names = ModZipInstaller.pathNamesFromSevenZipListing(listing)
        #expect(ModZipInstaller.containsTraversalPath(names))
    }

    @Test func sevenZipListingIgnoresSizeLines() {
        let listing = "Path = a\nSize = 10\nPath = b"
        #expect(ModZipInstaller.pathNamesFromSevenZipListing(listing) == ["a", "b"])
    }
}
