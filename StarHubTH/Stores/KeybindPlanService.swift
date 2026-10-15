import Foundation
import Observation

/// Plan de raccourcis (spec 2026-10-15 §5-§6) — calcule le plan, puis l'écrit
/// dans les vrais `config.json` des mods. C'est la seule écriture de la
/// fonctionnalité : chaque garde ici protège un fichier de l'utilisateur.
///
/// Ordre d'`apply`, et pourquoi : jeu ouvert refusé (un mod C# réécrit sa
/// config quand il veut) ; plan périmé refusé (le rapport a bougé depuis le
/// calcul) ; **sauvegarde d'abord** — si elle échoue, rien n'est écrit ;
/// puis un fichier à la fois, chacun isolé : un fichier en échec est sauté et
/// nommé, les autres s'écrivent quand même — jamais tout ou rien, jamais un
/// fichier à moitié réécrit.
@MainActor
@Observable
final class KeybindPlanService {
    struct AppliedResult: Equatable, Sendable {
        let written: Int
        /// `folderName` + raison en clair, affiché tel quel.
        let skipped: [String]
        /// Le lot de `ModConfigBackupManager` qui rend l'état d'avant plan.
        let backupId: String?
    }

    enum State: Equatable {
        case idle, computing, ready(KeybindPlan), applying, applied(AppliedResult), failed(String)
    }

    private(set) var state: State = .idle

    private static let configFile = "config.json"

    @ObservationIgnored private let backupManager: ModConfigBackupManager
    @ObservationIgnored private let isGameRunning: @MainActor () -> Bool
    /// Les réglages sur lesquels le plan a été calculé : la signature
    /// anti-péremption comparée par `apply`.
    @ObservationIgnored private var plannedSettings: [KeybindScanner.SettingBinding]?
    /// Le lot du dernier `apply` et les mods effectivement écrits — seuls
    /// ceux-là sont restaurés : rendre un fichier sauté n'apporte rien et
    /// pourrait écraser une édition faite depuis.
    @ObservationIgnored private var lastApply: (backup: ModConfigBackup, written: Set<String>)?

    /// `isGameRunning` n'a pas de valeur par défaut, contrairement au brief :
    /// une sonde oubliée qui répondrait toujours « fermé » laisserait écrire
    /// jeu ouvert sans que rien ne le signale.
    init(backupManager: ModConfigBackupManager = ModConfigBackupManager(),
         isGameRunning: @escaping @MainActor () -> Bool) {
        self.backupManager = backupManager
        self.isGameRunning = isGameRunning
    }

    /// L'annulation n'a de sens que tant que le lot du plan est le dernier :
    /// après lui, une autre sauvegarde décrit un état plus récent.
    var canUndo: Bool {
        guard let lastApply else { return false }
        return backupManager.loadBackups().first?.folderName == lastApply.backup.folderName
    }

    // MARK: - Calcul

    /// Fusionne familles devinées + corrections (une correction gagne
    /// toujours), puis appelle le solveur.
    /// `mods` : réservé à l'appelant (même lot que `apply`) ; le rapport porte
    /// déjà tout ce que le calcul lit.
    func compute(report: KeybindScanner.KeybindReport, mods: [ModItem],
                 familyStore: KeybindFamilyStore, mode: KeybindPlanMode) {
        state = .computing
        var families = Self.guessedFamilies(report)
        families.merge(familyStore.families) { _, correction in correction }
        let plan = KeybindPlanner.plan(report: report, families: families, mode: mode,
                                       chordCapable: Self.chordCapable(report))
        plannedSettings = report.settings
        state = .ready(plan)
    }

    /// Déduction par mod : nom, dernier segment de chaque réglage, et
    /// `ownMode` relevé sur au moins un réglage. Pas de catégorie Nexus :
    /// `ModItem` n'en porte aucune (R11).
    static func guessedFamilies(_ report: KeybindScanner.KeybindReport) -> [String: KeybindFamily] {
        var byMod: [String: (name: String, settingNames: [String], ownMode: Bool)] = [:]
        for setting in report.settings {
            var entry = byMod[setting.modID] ?? (setting.modName, [], false)
            if let last = setting.keyPath.last { entry.settingNames.append(last) }
            if report.settingContexts[KeybindScanner.settingKey(setting.modID, setting.keyPath)] == .ownMode {
                entry.ownMode = true
            }
            byMod[setting.modID] = entry
        }
        return byMod.compactMapValues {
            KeybindFamilyGuess.guess(modName: $0.name, settingNames: $0.settingNames,
                                     nexusCategory: nil, hasOwnModeContext: $0.ownMode)
        }
    }

    /// Les réglages qui portent déjà une liste ou une corde : seuls eux
    /// acceptent un repli `modificateur + touche`.
    static func chordCapable(_ report: KeybindScanner.KeybindReport) -> Set<String> {
        Set(report.settings
            .filter { $0.combos.count > 1 || $0.combos.contains { $0.buttons.count > 1 } }
            .map { $0.modID + "/" + $0.keyPath.joined(separator: ".") })
    }

    // MARK: - Application

    /// `report` : le rapport **courant** de l'appelant, comparé à celui du
    /// calcul. `rescan` est rejoué après toute écriture.
    func apply(report: KeybindScanner.KeybindReport, gameDir: String, mods: [ModItem],
               rescan: @escaping @MainActor () -> Void) async {
        guard case .ready(let plan) = state, let plannedSettings else {
            state = .failed("aucun plan à appliquer")
            return
        }
        guard !isGameRunning() else {
            state = .failed("jeu ouvert : fermez Stardew Valley avant d'appliquer le plan")
            return
        }
        guard report.settings == plannedSettings else {
            state = .failed("plan périmé, recalculer")
            return
        }
        guard !gameDir.isEmpty else {
            state = .failed("dossier du jeu inconnu")
            return
        }
        state = .applying

        var skipped: [String] = []
        var targets: [(mod: ModItem, moves: [PlannedMove])] = []
        let candidates = mods.flattenedMods.filter { !$0.isGroup }
        for (modID, moves) in Self.grouped(plan.moves) {
            // `X` actif et `.X` en pause partagent leur `folderName` : le plan
            // ne déplace que des réglages de mods actifs, c'est donc l'entrée
            // active qui a été scannée.
            let entries = candidates.filter { $0.folderName == modID }
            guard let mod = entries.first(where: \.isEnabled) ?? entries.first else {
                skipped.append("\(modID) : mod introuvable dans le parc")
                continue
            }
            targets.append((mod, moves))
        }
        guard !targets.isEmpty else {
            state = .applied(AppliedResult(written: 0, skipped: skipped, backupId: nil))
            return
        }

        // Sauvegarde avant toute écriture. `onlyEnabled: false` : un mod mis
        // en pause depuis le calcul est quand même sauvegardé (puis sauté).
        let backup: ModConfigBackup
        do {
            backup = try backupManager.createBackup(gameDir: gameDir, mods: targets.map(\.mod),
                                                    onlyEnabled: false)
        } catch {
            state = .failed("sauvegarde impossible, rien n'a été écrit : \(error.localizedDescription)")
            return
        }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        var written = Set<String>()
        for (mod, moves) in targets {
            guard mod.isEnabled else {
                skipped.append("\(mod.folderName) : mod en pause, configuration laissée telle quelle")
                continue
            }
            let folder = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
            if let reason = Self.rewrite(folder: folder, moves: moves) {
                skipped.append("\(mod.folderName) : \(reason)")
            } else {
                written.insert(mod.folderName)
            }
        }

        lastApply = (backup, written)
        state = .applied(AppliedResult(written: written.count, skipped: skipped,
                                       backupId: backup.folderName))
        rescan()
    }

    /// Les déplacements par mod, dans l'ordre du plan (déjà trié).
    private static func grouped(_ moves: [PlannedMove]) -> [(String, [PlannedMove])] {
        var order: [String] = []
        var byMod: [String: [PlannedMove]] = [:]
        for move in moves {
            if byMod[move.modID] == nil { order.append(move.modID) }
            byMod[move.modID, default: []].append(move)
        }
        return order.map { ($0, byMod[$0] ?? []) }
    }

    /// Réécrit le `config.json` de `folder` avec tous ses déplacements.
    /// Rend `nil` si le fichier est écrit, sinon la raison du saut — et rien
    /// n'est alors écrit : un seul déplacement en échec garde le fichier
    /// intact plutôt qu'à moitié appliqué.
    private static func rewrite(folder: String, moves: [PlannedMove]) -> String? {
        let path = (folder as NSString).appendingPathComponent(configFile)
        guard case .content(let loaded) = ModConfigWriteGuard.readDisk(atPath: path) else {
            return "config.json absent ou illisible"
        }
        // Plusieurs alternatives perdantes d'un même réglage : chacune
        // s'applique sur le texte déjà réécrit par la précédente.
        var text = loaded
        for move in moves {
            switch KeybindPlanWriter.rewrittenText(original: text, keyPath: move.keyPath,
                                                   from: move.from, to: move.to) {
            case .success(let next): text = next
            case .failure(let failure): return describe(failure, move)
            }
        }
        switch ModConfigWriteGuard.decide(loaded: loaded, onDisk: ModConfigWriteGuard.readDisk(atPath: path),
                                          pending: text) {
        case .proceed: break
        case .externallyChanged: return "config.json modifié pendant l'application"
        case .unverifiable: return "config.json illisible à la relecture"
        }
        do {
            try write(text, toFile: path, folder: folder)
            return nil
        } catch {
            return "écriture impossible : \(error.localizedDescription)"
        }
    }

    /// X7 : une part du parc a ses dossiers en `0555` (droits restitués par
    /// l'archive). Sur un refus de droits, le dossier est ouvert une fois,
    /// puis l'écriture est retentée.
    private static func write(_ text: String, toFile path: String, folder: String) throws {
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func describe(_ failure: KeybindPlanWriter.Failure, _ move: PlannedMove) -> String {
        let setting = move.keyPath.joined(separator: ".")
        switch failure {
        case .unreadable: return "config.json illisible (JSON invalide)"
        case .pathMissing: return "réglage \(setting) introuvable"
        case .alternativeMissing: return "touche \(move.from.display) absente de \(setting)"
        case .unsupportedValue: return "valeur de \(setting) non textuelle"
        }
    }

    // MARK: - Annulation

    /// Restaure les mods écrits par le dernier `apply` depuis son lot, puis
    /// rejoue `rescan`. Refusé si un autre lot a suivi.
    func undo(gameDir: String, mods: [ModItem], rescan: @escaping @MainActor () -> Void) async {
        guard let lastApply else {
            state = .failed("aucun plan appliqué à annuler")
            return
        }
        guard !isGameRunning() else {
            state = .failed("jeu ouvert : fermez Stardew Valley avant d'annuler le plan")
            return
        }
        guard canUndo else {
            state = .failed("une sauvegarde plus récente a suivi le plan : restaurez depuis l'écran des sauvegardes")
            return
        }
        // Le lot porte aussi les traductions (`ModConfigFiles.preservable`) :
        // seul `config.json` est rendu, le plan n'a rien écrit d'autre — une
        // traduction retouchée depuis ne doit pas être ramenée en arrière.
        let items = lastApply.backup.items
            .filter { lastApply.written.contains($0.modFolderName) }
            .map { item in
                ModConfigBackupItem(modFolderName: item.modFolderName, parentFolderName: item.parentFolderName,
                                    modDisplayName: item.modDisplayName,
                                    files: item.files.filter { $0 == Self.configFile },
                                    fileSizes: item.fileSizes.filter { $0.key == Self.configFile })
            }
        let report: ModConfigRestoreReport
        do {
            report = try backupManager.restoreBackup(gameDir: gameDir, backup: lastApply.backup,
                                                     selectedItems: items, currentMods: mods)
        } catch {
            state = .failed("annulation impossible : \(error.localizedDescription)")
            return
        }
        self.lastApply = nil
        let missed = report.skippedMods + report.skippedFiles
        state = missed.isEmpty ? .idle : .failed("annulation partielle, non restaurés : "
                                                 + missed.joined(separator: ", "))
        rescan()
    }
}
