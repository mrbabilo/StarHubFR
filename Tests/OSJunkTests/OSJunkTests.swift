import Testing
@testable import StarHubTHCore

/// La définition du résidu système existait en quatre exemplaires, dont un
/// amputé. Le scan des mods traitant tout dossier en `.` comme un mod en pause,
/// une entrée oubliée s'y affichait comme un mod désactivé.
struct OSJunkTests {
    @Test func macOSAndWindowsLitterIsRecognised() {
        #expect(OSJunk.isJunk(".DS_Store"))
        #expect(OSJunk.isJunk("Thumbs.db"))
        #expect(OSJunk.isJunk("ehthumbs.db"))
    }

    @Test func metadataFoldersAreRecognised() {
        // Les trois que le scan ignorait.
        #expect(OSJunk.isJunk("__MACOSX"))
        #expect(OSJunk.isJunk(".Spotlight-V100"))
        #expect(OSJunk.isJunk(".Trashes"))
    }

    @Test func theCustomFolderIconCarriesACarriageReturn() {
        // « Icon\r » porte réellement ce caractère : sans lui, aucune
        // correspondance.
        #expect(OSJunk.isJunk("Icon\r"))
        #expect(!OSJunk.isJunk("Icon"))
    }

    @Test func appleDoubleResourceForksAreRecognisedByPrefix() {
        #expect(OSJunk.isJunk("._MonMod"))
        #expect(OSJunk.isJunk("._"))
    }

    @Test func aRealModIsNotJunk() {
        #expect(!OSJunk.isJunk("Automate"))
        #expect(!OSJunk.isJunk(".Automate"))   // un mod en pause reste un mod
        #expect(!OSJunk.isJunk("DS_Store"))
    }
}
