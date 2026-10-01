import Foundation
import Testing
@testable import StarHubTHCore

struct ProbeLoadOrderTests {
    @Test func theRuleFollowsConsentAndTheProbe() {
        #expect(ProbeLoadOrder.wanted(consent: nil, probeActive: true) == nil)     // jamais demandé : ne rien toucher
        #expect(ProbeLoadOrder.wanted(consent: true, probeActive: true) == true)
        // Review Focus 5 : sonde en pause → retirer, sinon WARN SMAPI à chaque lancement.
        #expect(ProbeLoadOrder.wanted(consent: true, probeActive: false) == false)
        #expect(ProbeLoadOrder.wanted(consent: false, probeActive: true) == false)
    }

    @Test func syncWritesOnceKeepsABackupAndThenRemoves() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let internalDir = dir.appendingPathComponent("smapi-internal")
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        let file = internalDir.appendingPathComponent("config.user.json")
        let original = "{\n  \"ConsoleColorScheme\": \"LightBackground\"\n}"
        try original.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: true))
        #expect(SmapiUserConfig.listsLoadEarly(try String(contentsOf: file, encoding: .utf8), modId: BenchmarkSides.probeId))
        let backup = file.appendingPathExtension("starhubfr.bak")   // config.user.json.starhubfr.bak
        #expect(try String(contentsOf: backup, encoding: .utf8) == original)
        #expect(!ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: true))   // déjà en place
        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: false))
        #expect(!SmapiUserConfig.listsLoadEarly(try String(contentsOf: file, encoding: .utf8), modId: BenchmarkSides.probeId))
        #expect(!ProbeLoadOrder.sync(gameDir: dir.path, consent: nil, probeActive: true))   // sans avis : rien
    }
}
