import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct SmapiInstallerLimitsTests {

    @Test func aNormalRunIsNeverCut() {
        // Quelques dizaines de lignes : l'ordre de grandeur d'un déroulement
        // qui aboutit.
        let limits = SmapiInstallerLimits.standard
        #expect(limits.abort(bytesRead: 3_000, elapsed: 12) == nil)
        #expect(limits.abort(bytesRead: 0, elapsed: 0) == nil)
    }

    @Test func theFloodIsCutOnVolume() {
        // Le débit mesuré le 2026-09-04 : 119 827 838 octets en 20 s. Le
        // plafond tombe donc en une fraction de seconde, très avant la borne
        // de durée.
        let limits = SmapiInstallerLimits.standard
        let bytesPerSecond = 119_827_838.0 / 20.0
        let elapsedAtCap = Double(limits.maxBytes) / bytesPerSecond
        #expect(elapsedAtCap < 1.0)
        #expect(limits.abort(bytesRead: limits.maxBytes + 1, elapsed: elapsedAtCap) == .tooMuchOutput)
    }

    @Test func theCapIsExclusiveAtTheBoundary() {
        let limits = SmapiInstallerLimits(maxBytes: 100, maxDuration: 10)
        #expect(limits.abort(bytesRead: 100, elapsed: 10) == nil)
        #expect(limits.abort(bytesRead: 101, elapsed: 10) == .tooMuchOutput)
        #expect(limits.abort(bytesRead: 100, elapsed: 10.1) == .timedOut)
    }

    @Test func volumeIsAnsweredBeforeDuration() {
        // Les deux dépassés : c'est le volume qu'on a mesuré, c'est lui qu'on
        // nomme — le message à l'utilisateur en dépend.
        let limits = SmapiInstallerLimits(maxBytes: 10, maxDuration: 1)
        #expect(limits.abort(bytesRead: 999, elapsed: 999) == .tooMuchOutput)
    }
}

/// La ligne d'erreur montrée à l'utilisateur — jamais testée jusqu'ici, alors
/// qu'elle porte **tout** ce qu'il apprend d'un échec.
@Suite struct SmapiInstallerOutputTests {

    @Test func theExceptionLineWinsOverTheStackTrace() {
        let output = """
        Extracting install files...
        Oops! An unexpected exception occurred: System.IO.IOException: nope
           at StardewModdingAPI.Installer.Program.Main(String[] args)
           at System.RuntimeMethodHandle.InvokeMethod()
        """
        #expect(SmapiInstallerOutput.lastMeaningfulLine(of: output)
            == "Oops! An unexpected exception occurred: System.IO.IOException: nope")
    }

    @Test func aFailureLineIsPreferredToWhateverFollows() {
        let output = "Copying files...\nThe install failed: could not write\nPress any key.\n"
        #expect(SmapiInstallerOutput.lastMeaningfulLine(of: output)
            == "The install failed: could not write")
    }

    @Test func withoutAKnownMarkerTheLastNonEmptyLineIsUsed() {
        let output = "Step one\nStep two\n\n   \n"
        #expect(SmapiInstallerOutput.lastMeaningfulLine(of: output) == "Step two")
    }

    @Test func emptyOutputStillSaysSomething() {
        #expect(SmapiInstallerOutput.lastMeaningfulLine(of: "") == "unknown error")
        #expect(SmapiInstallerOutput.lastMeaningfulLine(of: "\n \n") == "unknown error")
    }

    @Test func carriageReturnsCountAsLineBreaks() {
        // La sortie d'un programme .NET peut porter des fins de ligne CRLF ;
        // `components(separatedBy: .newlines)` les découpe, et l'espace
        // résiduel est retiré. Un `\r` traînant collerait sinon au message.
        let output = "Working...\r\nThe install failed: disk full\r\n"
        #expect(SmapiInstallerOutput.lastMeaningfulLine(of: output)
            == "The install failed: disk full")
    }
}
