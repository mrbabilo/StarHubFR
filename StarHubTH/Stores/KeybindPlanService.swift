import Foundation
import Observation

/// Plan de raccourcis (spec 2026-10-15 §5-§6) — calcule le plan, puis l'écrit
/// dans les vrais `config.json` des mods. C'est la seule écriture de la
/// fonctionnalité : chaque garde ici protège un fichier de l'utilisateur.
///
/// Ordre d'`apply`, et pourquoi : jeu ouvert refusé (un mod C# réécrit sa
/// config quand il veut) ; plan périmé refusé (le rapport a bougé depuis le
/// calcul) ; **sauvegarde d'abord** — si elle échoue, rien n'est écrit, et un
/// fichier absent du lot n'est jamais écrit ; puis un fichier à la fois,
/// chacun isolé : un fichier en échec est sauté et nommé, les autres
/// s'écrivent quand même — jamais tout ou rien, jamais un fichier à moitié
/// réécrit. Résultats et refus typés : `KeybindPlanService+Outcome.swift`.
@MainActor
@Observable
final class KeybindPlanService {
    private(set) var state: State = .idle
    /// Un refus qui ne change pas l'état — jeu ouvert : le plan prêt (ou
    /// l'annulation possible) reste, l'utilisateur ferme le jeu et réessaie.
    /// Effacé à l'opération suivante.
    private(set) var refusal: Failure?

    private static let configFile = "config.json"

    @ObservationIgnored private let backupManager: ModConfigBackupManager
    @ObservationIgnored private let isGameRunning: @MainActor () -> Bool
    /// Les réglages sur lesquels le plan a été calculé : la signature
    /// anti-péremption comparée par `apply`.
    @ObservationIgnored private var plannedSettings: [KeybindScanner.SettingBinding]?
    /// Le lot du dernier `apply` et, par mod écrit, le chemin et le texte
    /// exact écrits. Seuls ces mods sont restaurés, et seulement si le
    /// fichier porte encore ce texte : `backUpConfigOncePerDay` ne crée pas
    /// de nouveau lot quand celui du plan protège déjà le fichier — le lot du
    /// plan reste « le dernier » alors que l'utilisateur a pu éditer depuis.
    @ObservationIgnored private var lastApply: (backup: ModConfigBackup,
                                                written: [String: (path: String, text: String)])?

    /// `isGameRunning` n'a pas de valeur par défaut : une sonde oubliée qui
    /// répondrait toujours « fermé » laisserait écrire jeu ouvert sans que
    /// rien ne le signale.
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
    func compute(report: KeybindScanner.KeybindReport, familyStore: KeybindFamilyStore,
                 mode: KeybindPlanMode) {
        refusal = nil
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
            // Le nom du réglage, index de tableau retirés : `DumpKeys.[0]`
            // se devine sur « DumpKeys », pas sur « [0] ».
            if let last = KeybindPlanner.settingName(setting.keyPath).last { entry.settingNames.append(last) }
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
    /// calcul. `excluding` : ids de `PlannedMove` retirés par l'utilisateur,
    /// ni sauvegardés ni écrits. `rescan` est rejoué après la sauvegarde.
    /// Un second appel arrivé sur `.applying`/`.applied` (double clic mis en
    /// file) rend la main sans rien toucher : le verdict affiché reste.
    func apply(report: KeybindScanner.KeybindReport, gameDir: String, mods: [ModItem],
               excluding: Set<String> = [], rescan: @escaping @MainActor () -> Void) async {
        switch state {
        case .applying, .applied: return
        case .idle, .computing, .ready, .undone, .failed: break
        }
        refusal = nil
        guard case .ready(let plan) = state, let plannedSettings else { state = .failed(.noPlan); return }
        guard !isGameRunning() else { refusal = .gameRunning; return }
        guard report.settings == plannedSettings else { state = .failed(.stalePlan); return }
        guard !gameDir.isEmpty else { state = .failed(.noGameDir); return }
        state = .applying

        var skipped: [Skip] = []
        var targets: [(mod: ModItem, moves: [PlannedMove])] = []
        let candidates = mods.flattenedMods.filter { !$0.isGroup }
        for (modID, moves) in Self.grouped(plan.moves.filter { !excluding.contains($0.id) }) {
            // `X` actif et `.X` en pause partagent leur `folderName` : le plan
            // ne déplace que des réglages de mods actifs, c'est donc l'entrée
            // active qui a été scannée.
            let entries = candidates.filter { $0.folderName == modID }
            guard let mod = entries.first(where: \.isEnabled) ?? entries.first else {
                skipped.append(Skip(folderName: modID, reason: .modNotFound))
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
            state = .failed(.backupFailed(error.localizedDescription))
            return
        }

        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        let backupRoot = backupManager.backupsDirectory.appendingPathComponent(backup.folderName)
        var written: [String: (path: String, text: String)] = [:]
        for (mod, moves) in targets {
            guard mod.isEnabled else {
                skipped.append(Skip(folderName: mod.folderName, reason: .paused))
                continue
            }
            // `createBackup` saute en silence un dossier sans fichier
            // préservable — un dossier lié par symlink n'en livre aucun alors
            // que l'écriture, elle, le traverserait. Sans copie, pas d'écriture.
            guard let item = backup.items.first(where: { $0.modFolderName == mod.folderName }),
                  item.files.contains(Self.configFile) else {
                skipped.append(Skip(folderName: mod.folderName, reason: .noBackupCopy))
                continue
            }
            let target = Target(
                path: (modsPath as NSString).appendingPathComponent(mod.physicalFolderName + "/" + Self.configFile),
                backedUp: backupRoot.appendingPathComponent(item.modFolderName)
                    .appendingPathComponent(Self.configFile).path,
                modRoot: (modsPath as NSString).appendingPathComponent(
                    String(mod.physicalFolderName.split(separator: "/").first ?? ""))
            )
            switch Self.rewrite(target, moves: moves) {
            case .success(let text): written[mod.folderName] = (target.path, text)
            case .failure(let reason): skipped.append(Skip(folderName: mod.folderName, reason: reason))
            }
        }

        // Rien d'écrit : rien à annuler. Le lot créé a de toute façon pris
        // la place du précédent — l'ancien `lastApply` ne s'annule plus.
        if written.isEmpty { lastApply = nil } else { lastApply = (backup, written) }
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

    private struct Target {
        let path: String
        /// La copie de `config.json` dans le lot : le texte réécrit, et la
        /// référence du garde.
        let backedUp: String
        /// Le dossier de tête du mod : la remontée des droits s'y arrête.
        let modRoot: String
    }

    /// Réécrit le texte **sauvegardé** avec tous les déplacements du mod, et
    /// l'écrit si le disque porte encore ce texte. Rend le texte écrit, ou la
    /// raison du saut — rien n'est alors écrit.
    private static func rewrite(_ target: Target, moves: [PlannedMove]) -> Result<String, Skip.Reason> {
        let current: String
        switch ModConfigWriteGuard.readDisk(atPath: target.path) {
        case .missing: return .failure(.missing)   // jamais recréé
        case .unreadable: return .failure(.unreadable)
        case .content(let text): current = text
        }
        guard case .content(let loaded) = ModConfigWriteGuard.readDisk(atPath: target.backedUp) else {
            return .failure(.noBackupCopy)
        }
        // Plusieurs alternatives perdantes d'un même réglage : chacune
        // s'applique sur le texte déjà réécrit par la précédente.
        var text = loaded
        for move in moves {
            switch KeybindPlanWriter.rewrittenText(original: text, keyPath: move.keyPath,
                                                   from: move.from, to: move.to) {
            case .success(let next): text = next
            case .failure(let failure): return .failure(.writerFailed(failure, keyPath: move.keyPath))
            }
        }
        // Le disque doit porter ce qui a été sauvegardé : sinon il a bougé
        // depuis le lot, et l'écrire perdrait ce changement sans copie.
        switch ModConfigWriteGuard.decide(loaded: loaded, onDisk: .content(current), pending: text) {
        case .proceed: break
        case .externallyChanged: return .failure(.externallyChanged)
        case .unverifiable: return .failure(.unreadable)
        }
        do {
            // X7 : un dossier de mod en 0555 est ouvert le temps de l'écriture,
            // puis rendu à ses droits d'origine (même règle que la restauration).
            try RecoveredFileWriter.withWriteAccess(to: target.path, modRoot: target.modRoot) {
                try text.write(toFile: target.path, atomically: true, encoding: .utf8)
            }
            return .success(text)
        } catch {
            return .failure(.writeFailed(error.localizedDescription))
        }
    }

    // MARK: - Annulation

    /// Restaure, depuis le lot du dernier `apply`, le seul `config.json` des
    /// mods écrits — et seulement s'il porte encore le texte écrit par le
    /// plan. Refusé si un autre lot a suivi. `rescan` est rejoué ensuite.
    /// Un second appel arrivé sur `.undone` (double clic mis en file) rend
    /// la main sans rien toucher : le verdict affiché reste.
    func undo(gameDir: String, mods: [ModItem], rescan: @escaping @MainActor () -> Void) async {
        if case .undone = state { return }
        refusal = nil
        guard let lastApply else { state = .failed(.nothingToUndo); return }
        guard !isGameRunning() else { refusal = .gameRunning; return }
        guard canUndo else { state = .failed(.notLatestBackup); return }

        var skipped: [Skip] = []
        var items: [ModConfigBackupItem] = []
        for (folderName, write) in lastApply.written.sorted(by: { $0.key < $1.key }) {
            guard let item = lastApply.backup.items.first(where: { $0.modFolderName == folderName }),
                  item.files.contains(Self.configFile) else {
                skipped.append(Skip(folderName: folderName, reason: .noBackupCopy))
                continue
            }
            guard case .content(let current) = ModConfigWriteGuard.readDisk(atPath: write.path),
                  current == write.text else {
                skipped.append(Skip(folderName: folderName, reason: .changedSinceApply))
                continue
            }
            // Le lot porte aussi les traductions : seul `config.json` est
            // rendu, le plan n'a rien écrit d'autre.
            items.append(ModConfigBackupItem(modFolderName: item.modFolderName,
                                             parentFolderName: item.parentFolderName,
                                             modDisplayName: item.modDisplayName,
                                             files: [Self.configFile],
                                             fileSizes: item.fileSizes.filter { $0.key == Self.configFile }))
        }
        var restored = 0
        if !items.isEmpty {
            do {
                let report = try backupManager.restoreBackup(gameDir: gameDir, backup: lastApply.backup,
                                                             selectedItems: items, currentMods: mods)
                restored = report.modsRestored
                let suffix = "/" + Self.configFile
                skipped += (report.skippedMods + report.skippedFiles.map {
                    $0.hasSuffix(suffix) ? String($0.dropLast(suffix.count)) : $0
                }).map { Skip(folderName: $0, reason: .restoreFailed) }
            } catch {
                state = .failed(.restoreFailed(error.localizedDescription))
                return
            }
        }
        self.lastApply = nil
        state = .undone(UndoResult(restored: restored, skipped: skipped))
        rescan()
    }
}
