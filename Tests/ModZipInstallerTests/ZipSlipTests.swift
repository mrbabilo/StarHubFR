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

    @Test func sevenZipListingSkipsTheArchiveHeader() {
        // Sortie réelle de `7zz l -slt`, en-tête compris : le premier `Path =`
        // décrit **l'archive elle-même**, à son chemin absolu sur le disque.
        // Le prendre pour une entry faisait voir une évasion dans toute archive
        // saine, et rejetait donc tout `.7z` et tout `.rar` — mesuré sur le mod
        // Nexus 47840. Les entries ne commencent qu'après le séparateur.
        let listing = """
        7-Zip (z) 24.09 (arm64)

        Scanning the drive for archives:
        1 file, 81570 bytes (80 KiB)

        Listing archive: /Users/someone/mods tests/WarehouseAutomation.7z

        --
        Path = /Users/someone/mods tests/WarehouseAutomation.7z
        Type = 7z
        Physical Size = 81570
        Headers Size = 297
        Method = LZMA2:384k BCJ
        Solid = +
        Blocks = 2

        ----------
        Path = WarehouseAutomation
        Size = 0
        Folder = +

        Path = WarehouseAutomation/manifest.json
        Size = 412
        Folder = -
        """
        let names = ModZipInstaller.pathNamesFromSevenZipListing(listing)
        #expect(names == ["WarehouseAutomation", "WarehouseAutomation/manifest.json"])
        #expect(!ModZipInstaller.containsTraversalPath(names))
    }

    @Test func sevenZipListingStillCatchesTraversalAfterTheHeader() {
        // La garde doit rester mordante : l'en-tête écarté, une vraie entry
        // absolue doit toujours être vue.
        let listing = """
        --
        Path = /tmp/archive.7z
        Type = 7z

        ----------
        Path = ok.txt
        Path = /etc/passwd
        """
        let names = ModZipInstaller.pathNamesFromSevenZipListing(listing)
        #expect(ModZipInstaller.containsTraversalPath(names))
    }
}
