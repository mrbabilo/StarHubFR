import Foundation
import Testing
@testable import StarHubTHCore

/// UltraSmooth réglé le temps d'une mesure de la sonde, puis rétabli
/// (choix de l'auteur du 2026-11-11 : mesures seulement ; rien si
/// l'expérimental est actif ; rien d'écrasé si le fichier a changé).
struct UltraSmoothMeasureSettingTests {
    private typealias Setting = UltraSmoothMeasureSetting

    /// Forme du `config.json` du parc (Newtonsoft indenté, schéma 3).
    static func config(pacing: Bool = true, slicing: Bool? = true, experimental: Bool = false,
                       schema: Int = 3) -> String {
        var lines = ["  \"EnableMod\": true", "  \"ConfigSchemaVersion\": \(schema)",
                     "  \"EnableExperimentalFeatures\": \(experimental)"]
        if let slicing { lines.append("  \"EnableLocationTimeSlicing\": \(slicing)") }
        lines.append("  \"EnableTimeChangedPacing\": \(pacing)")
        lines.append("  \"TimeChangedBudgetMs\": 2.0")
        return "{\n" + lines.joined(separator: ",\n") + "\n}"
    }

    // MARK: - Règle

    @Test func bothOptionsAreTurnedOffAndNothingElseMoves() throws {
        guard case .write(let text) = Setting.plan(configText: Self.config()) else {
            Issue.record("écriture attendue"); return
        }
        #expect(text == Self.config(pacing: false, slicing: false))
    }

    @Test func onlyTheOptionStillOnIsTouched() {
        // Le parc de l'auteur : l'étalement des lieux déjà coupé à la main.
        #expect(Setting.plan(configText: Self.config(slicing: false))
                == .write(Self.config(pacing: false, slicing: false)))
    }

    @Test func anAbsentOptionIsOnByDefaultAndGetsWritten() throws {
        guard case .write(let text) = Setting.plan(configText: Self.config(slicing: nil)) else {
            Issue.record("écriture attendue"); return
        }
        #expect(text.contains("\"EnableLocationTimeSlicing\": false"))
        #expect(text.contains("\"EnableTimeChangedPacing\": false"))
    }

    @Test func alreadyOffWritesNothing() {
        #expect(Setting.plan(configText: Self.config(pacing: false, slicing: false)) == .alreadyOff)
    }

    /// UltraSmooth rallumerait les options au chargement : refus, pas d'écriture.
    @Test func experimentalAndOldSchemaAreRefused() {
        #expect(Setting.plan(configText: Self.config(experimental: true)) == .refused(.experimental))
        #expect(Setting.plan(configText: Self.config(schema: 2)) == .refused(.oldSchema))
        #expect(Setting.plan(configText: "{ \"EnableMod\": true }") == .refused(.oldSchema))
        #expect(Setting.plan(configText: "pas du json") == .refused(.unreadable))
    }

    @Test func theRestoreNeverOverwritesAChangedFile() {
        let snapshot = Setting.Snapshot(configPath: "/x", originalText: "A", writtenText: "B", lastAppliedAt: Date())
        #expect(Setting.restorePlan(current: "B", snapshot: snapshot) == .restore)
        #expect(Setting.restorePlan(current: "A", snapshot: snapshot) == .alreadyOriginal)
        #expect(Setting.restorePlan(current: "C", snapshot: snapshot) == .changedMeanwhile)
        #expect(Setting.restorePlan(current: nil, snapshot: snapshot) == .changedMeanwhile)
    }

    // MARK: - Disque

    private struct Park {
        let root: URL
        let state: URL
        let config: URL
        let mods: [ModItem]
        let backups: ModConfigBackupManager

        init(probe: Bool = true, ultraSmooth: Bool = true, text: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("USMeasure-\(UUID().uuidString)", isDirectory: true)
            state = root.appendingPathComponent("state", isDirectory: true)
            let folder = root.appendingPathComponent("Mods/UltraSmooth", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            config = folder.appendingPathComponent("config.json")
            try text.write(to: config, atomically: true, encoding: .utf8)
            func mod(_ id: String, _ folder: String, _ on: Bool) -> ModItem {
                ModItem(uniqueId: id, name: folder, folderName: folder, version: "1", author: "", description: "",
                        nexusUrl: "", nexusModId: "", isEnabled: on, dependencies: [])
            }
            mods = [mod(ModPresence.probeId, "StarHubFR.Probe", probe),
                    mod(Setting.uniqueId, "UltraSmooth", ultraSmooth)]
            backups = ModConfigBackupManager(backupsBasePath: root.appendingPathComponent("backups", isDirectory: true))
        }

        var text: String? { Setting.read(config) }
        func apply(at date: Date = Date()) -> Setting.ApplyOutcome {
            Setting.beforeMeasure(mods: mods, gameDir: root.path, backups: backups, stateDirectory: state, now: date)
        }
        func restore(running: Bool = false, exitedAt: Date) -> Setting.RestoreOutcome {
            Setting.afterMeasure(gameRunning: running, exitedAt: exitedAt, stateDirectory: state)
        }
    }

    @Test func aMeasureWritesThenTheExitRestoresTheOriginalByte() throws {
        let original = Self.config()
        let park = try Park(text: original)
        defer { try? FileManager.default.removeItem(at: park.root) }
        let launch = Date()
        #expect(park.apply(at: launch) == .applied)
        #expect(park.text == Self.config(pacing: false, slicing: false))
        // Jeu encore lancé, puis sortie antérieure au lancement : pas encore.
        #expect(park.restore(running: true, exitedAt: launch.addingTimeInterval(60)) == .notYet)
        #expect(park.restore(exitedAt: launch.addingTimeInterval(-1)) == .notYet)
        #expect(park.restore(exitedAt: launch.addingTimeInterval(60)) == .restored)
        #expect(park.text == original)
        #expect(park.restore(exitedAt: Date()) == .nothingPending)
    }

    /// Une série relance après chaque sortie : le second lancement ne réécrit
    /// rien et repousse la remise.
    @Test func aSeriesKeepsTheSettingAcrossRelaunches() throws {
        let original = Self.config()
        let park = try Park(text: original)
        defer { try? FileManager.default.removeItem(at: park.root) }
        let first = Date()
        #expect(park.apply(at: first) == .applied)
        let second = first.addingTimeInterval(30)
        #expect(park.apply(at: second) == .applied)
        // La sortie du premier côté, vue après le second lancement.
        #expect(park.restore(exitedAt: first.addingTimeInterval(20)) == .notYet)
        #expect(park.restore(exitedAt: second.addingTimeInterval(60)) == .restored)
        #expect(park.text == original)
    }

    @Test func aFileChangedDuringTheMeasureIsLeftAlone() throws {
        let park = try Park(text: Self.config())
        defer { try? FileManager.default.removeItem(at: park.root) }
        let launch = Date()
        #expect(park.apply(at: launch) == .applied)
        let edited = Self.config(pacing: false, slicing: false) + "\n"
        try edited.write(to: park.config, atomically: true, encoding: .utf8)
        #expect(park.restore(exitedAt: launch.addingTimeInterval(60)) == .changedMeanwhile)
        #expect(park.text == edited)
        #expect(park.restore(exitedAt: Date()) == .nothingPending)
    }

    @Test func nothingIsTouchedWithoutBothModsActiveOrWhenRefused() throws {
        let original = Self.config()
        for park in [try Park(probe: false, text: original), try Park(ultraSmooth: false, text: original)] {
            defer { try? FileManager.default.removeItem(at: park.root) }
            #expect(park.apply() == .notNeeded)
            #expect(park.text == original)
        }
        let experimental = Self.config(experimental: true)
        let park = try Park(text: experimental)
        defer { try? FileManager.default.removeItem(at: park.root) }
        #expect(park.apply() == .refused(.experimental))
        #expect(park.text == experimental)
        #expect(park.restore(exitedAt: Date()) == .nothingPending)
    }
}
