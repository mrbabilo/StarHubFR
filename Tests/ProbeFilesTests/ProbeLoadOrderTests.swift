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

        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: true) == .written)
        #expect(SmapiUserConfig.listsLoadEarly(try String(contentsOf: file, encoding: .utf8), modId: BenchmarkSides.probeId))
        let backup = file.appendingPathExtension("starhubfr.bak")   // config.user.json.starhubfr.bak
        #expect(try String(contentsOf: backup, encoding: .utf8) == original)
        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: true) == .unchanged)   // déjà en place
        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: false) == .written)
        #expect(!SmapiUserConfig.listsLoadEarly(try String(contentsOf: file, encoding: .utf8), modId: BenchmarkSides.probeId))
        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: nil, probeActive: true) == .unchanged)   // sans avis : rien
    }

    private func makeGameDir(config: Data?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let internalDir = dir.appendingPathComponent("smapi-internal")
        try FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
        if let config { try config.write(to: internalDir.appendingPathComponent("config.user.json")) }
        return dir
    }

    /// Un fichier présent mais illisible n'est ni écrasé ni copié : le lire
    /// comme vide le remplaçait par `{"ModsToLoadEarly": [...]}` sans `.bak`.
    @Test func anUnreadableFileIsNeverOverwritten() throws {
        let bytes = Data([0x7B, 0x22, 0xC3, 0x28, 0x22, 0x3A, 0x31, 0x7D])   // {"\xC3(":1} — UTF-8 invalide
        let dir = try makeGameDir(config: bytes)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = ProbeLoadOrder.configURL(gameDir: dir.path)

        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: true) == .failed)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(!FileManager.default.fileExists(atPath: file.appendingPathExtension("starhubfr.bak").path))
    }

    @Test func aRefusedEditIsAFailureNotANoOp() throws {
        // Entrée exotique : SmapiUserConfig refuse d'écrire plutôt que perdre l'entrée.
        let dir = try makeGameDir(config: Data("{ \"ModsToLoadEarly\": [42] }".utf8))
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: true) == .failed)
    }

    @Test func aMissingFileIsCreatedAndAMissingSmapiFails() throws {
        let dir = try makeGameDir(config: nil)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: true) == .written)
        #expect(ProbeLoadOrder.listed(gameDir: dir.path) == true)

        let bare = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(ProbeLoadOrder.sync(gameDir: bare.path, consent: true, probeActive: true) == .failed)
        #expect(ProbeLoadOrder.sync(gameDir: bare.path, consent: true, probeActive: false) == .unchanged)   // rien à retirer
        #expect(ProbeLoadOrder.listed(gameDir: bare.path) == nil)
        #expect(ProbeLoadOrder.listed(gameDir: "") == nil)
    }

    @Test func theStatusComesFromTheFileAndTheLastLaunch() {
        typealias S = ProbeLoadOrder.Status
        func s(_ c: Bool?, _ a: Bool, _ l: Bool?, _ f: Bool?) -> S {
            ProbeLoadOrder.status(consent: c, probeActive: a, listed: l, lastLaunchFirst: f)
        }
        #expect(s(nil, true, false, false) == .notAsked)
        #expect(s(false, true, false, false) == .declined)
        #expect(s(true, true, true, true) == .active)
        #expect(s(true, true, true, false) == .pending)     // consenti après le dernier lancement
        #expect(s(true, true, true, nil) == .pending)
        #expect(s(true, true, false, true) == .notApplied)  // écriture échouée, ou fichier remis par l'auteur
        #expect(s(true, false, false, true) == .probePaused)
        #expect(s(true, true, nil, true) == .smapiMissing)
    }

    /// Sonde en pause (retirée au lancement), puis réactivée dans la liste :
    /// la carte réconcilie au lieu d'annoncer un échec d'écriture.
    @Test func reactivatingThePausedProbeIsPendingNotAFailure() throws {
        let dir = try makeGameDir(config: Data("{}".utf8))
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = ProbeLoadOrder.reconcile(gameDir: dir.path, consent: true, probeActive: true)
        #expect(ProbeLoadOrder.sync(gameDir: dir.path, consent: true, probeActive: false) == .written)   // lancement, sonde en pause
        let listed = ProbeLoadOrder.reconcile(gameDir: dir.path, consent: true, probeActive: true)        // réactivée, carte affichée
        #expect(listed == true)
        #expect(ProbeLoadOrder.status(consent: true, probeActive: true, listed: listed, lastLaunchFirst: false) == .pending)
    }
}
