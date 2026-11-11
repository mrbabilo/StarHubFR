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

    /// Un réglage changé pendant la partie (GMCM, `us_…`) : rien d'écrasé.
    @Test func aFileChangedDuringTheMeasureIsLeftAlone() throws {
        let park = try Park(text: Self.config())
        defer { try? FileManager.default.removeItem(at: park.root) }
        let launch = Date()
        #expect(park.apply(at: launch) == .applied)
        let edited = Self.smapiRewrite(Self.config(pacing: false, slicing: false))
            .replacingOccurrences(of: "\"TimeChangedBudgetMs\" : 2", with: "\"TimeChangedBudgetMs\" : 5")
        #expect(edited.contains("\"TimeChangedBudgetMs\" : 5"))
        try edited.write(to: park.config, atomically: true, encoding: .utf8)
        #expect(park.restore(exitedAt: launch.addingTimeInterval(60)) == .changedMeanwhile)
        #expect(park.text == edited)
        #expect(park.restore(exitedAt: Date()) == .nothingPending)
    }

    // MARK: - Réécriture par SMAPI

    /// Ce que fait SMAPI à chaque lancement (`ReadConfig` → `WriteConfig`) :
    /// commentaires retirés, autre mise en forme, clés réordonnées, champ
    /// manquant ajouté. Imité ici par `JSONSerialization` (clés triées,
    /// `" : "`, `2.0` écrit `2`).
    static func smapiRewrite(_ text: String, adding extra: [String: Any] = ["AddedBySmapi": 1]) -> String {
        guard var object = Setting.object(text) else { return text }
        object.merge(extra) { current, _ in current }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let rewritten = String(data: data, encoding: .utf8) else { return text }
        return rewritten
    }

    /// Le défaut corrigé : comparée aux octets, une config réécrite par SMAPI
    /// passait pour « modifiée pendant la mesure », et les deux options
    /// restaient coupées. L'original, commenté à la main, revient tel quel.
    @Test func aConfigRewrittenBySmapiIsStillRestored() throws {
        let original = "{\n    // réglé à la main\n" + Self.config().dropFirst(2)
        let park = try Park(text: original)
        defer { try? FileManager.default.removeItem(at: park.root) }
        let launch = Date()
        #expect(park.apply(at: launch) == .applied)
        let rewritten = Self.smapiRewrite(park.text ?? "")
        #expect(rewritten != park.text)
        try rewritten.write(to: park.config, atomically: true, encoding: .utf8)
        #expect(park.restore(exitedAt: launch.addingTimeInterval(60)) == .restored)
        #expect(park.text == original)
    }

    /// Une série : SMAPI a réécrit le fichier entre deux côtés. Le second
    /// lancement reconnaît le réglage et repousse la remise, au lieu de
    /// répondre « déjà coupé » et de laisser la sortie suivante échouer.
    @Test func aSeriesRecognisesItsSettingAfterASmapiRewrite() throws {
        let original = Self.config()
        let park = try Park(text: original)
        defer { try? FileManager.default.removeItem(at: park.root) }
        let first = Date()
        #expect(park.apply(at: first) == .applied)
        try Self.smapiRewrite(park.text ?? "").write(to: park.config, atomically: true, encoding: .utf8)
        let second = first.addingTimeInterval(30)
        #expect(park.apply(at: second) == .applied)
        #expect(park.restore(exitedAt: first.addingTimeInterval(20)) == .notYet)
        #expect(park.restore(exitedAt: second.addingTimeInterval(60)) == .restored)
        #expect(park.text == original)
    }

    /// Option absente de l'original (défaut `true`), ajoutée coupée en tête
    /// par l'app, remise à sa place par SMAPI : la remise se fait. Retrouvée
    /// coupée alors qu'une autre a été rallumée par le joueur : rien d'écrasé.
    @Test func anAbsentOptionIsJudgedByItsDefault() {
        let original = Self.config(slicing: nil)
        guard case .write(let written) = Setting.plan(configText: original) else {
            Issue.record("écriture attendue"); return
        }
        let snapshot = Setting.Snapshot(configPath: "/x", originalText: original, writtenText: written,
                                        lastAppliedAt: Date())
        #expect(Setting.restorePlan(current: Self.smapiRewrite(written), snapshot: snapshot) == .restore)
        #expect(Setting.restorePlan(current: Self.smapiRewrite(Self.config(slicing: true)), snapshot: snapshot)
                == .alreadyOriginal)
        #expect(Setting.restorePlan(current: Self.smapiRewrite(Self.config(pacing: true, slicing: false)),
                                    snapshot: snapshot) == .changedMeanwhile)
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
