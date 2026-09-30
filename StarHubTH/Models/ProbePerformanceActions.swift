import Foundation

/// Les gestes que l'analyse recommande (spec §3d), réversibles : mise en pause,
/// sauvegardes d'installation, réglage d'avant. Jamais de suppression.
public enum ProbePerformanceActions {
    /// L'entrée de tête qui porte `modId` : un composant de pack se met en
    /// pause par son pack (le point vit sur l'entrée de tête). `nil` : le mod
    /// n'est plus installé — le geste ne s'affiche pas.
    public static func target(modId: String, in mods: [ModItem]) -> ModItem? {
        func matches(_ item: ModItem) -> Bool {
            !item.uniqueId.isEmpty && item.uniqueId.caseInsensitiveCompare(modId) == .orderedSame
        }
        return mods.first { matches($0) || ($0.children ?? []).contains(where: matches) }
    }

    public struct ProbePauseBlockers: Equatable, Sendable {
        /// Mods actifs qui exigent celui-ci : non vide = pas de geste.
        public let dependents: [String]
        /// Frères du pack de tête, mis en pause avec lui.
        public let siblings: [String]

        public init(dependents: [String], siblings: [String]) {
            self.dependents = dependents
            self.siblings = siblings
        }
    }

    /// D5-B — ce qui empêche ou accompagne la mise en pause d'un mod lourd :
    /// les mods actifs qui l'exigent (pas de geste : couper Content Patcher
    /// couperait ses packs), et les frères du pack de tête qui partent avec
    /// lui (le point vit sur l'entrée de tête).
    public static func pauseBlockers(modId: String, in mods: [ModItem]) -> ProbePauseBlockers {
        let key = modId.lowercased()
        let head = target(modId: modId, in: mods)
        let headIds = Set((head.map { [$0] + ($0.children ?? []) } ?? []).map { $0.uniqueId.lowercased() })
        var dependents: [String] = []
        for mod in mods.flatMap({ $0.isGroup ? ($0.children ?? []) : [$0] }) where mod.isEnabled {
            guard !headIds.contains(mod.uniqueId.lowercased()) else { continue }
            if mod.dependencies.contains(where: { $0.isRequired && $0.uniqueId.lowercased() == key }) {
                dependents.append(mod.name)
            }
        }
        let siblings = (head?.children ?? [])
            .filter { $0.uniqueId.lowercased() != key }
            .map(\.name)
        return ProbePauseBlockers(dependents: dependents.sorted(), siblings: siblings)
    }

    public enum RevertOutcome: Equatable, Sendable {
        case reverted
        case gameRunning
        /// `configs/<sha>.json` absent (la sonde ne range pas tout) ou
        /// empreinte illisible.
        case contentMissing
        /// `config.json` a bougé entre la lecture et l'écriture : rien écrit.
        case changedOnDisk
        case backupFailed(String)
        case writeFailed(String)
    }

    /// Réécrit `config.json` avec le contenu d'avant (`configs/<sha>.json`),
    /// jeu fermé, sauvegarde d'abord, garde anti-écrasement (patron de
    /// l'éditeur de config). Les contenus peuvent porter des clés d'API :
    /// jamais journalisés.
    public static func revertConfig(of mod: ModItem, toSha sha: String, configsDirectory: URL,
                                    gameDir: String, gameRunning: Bool,
                                    backups: ModConfigBackupManager) -> RevertOutcome {
        guard !gameRunning else { return .gameRunning }
        let fm = FileManager.default
        guard !sha.isEmpty, sha.allSatisfy(\.isHexDigit),
              let oldData = fm.contents(atPath: configsDirectory.appendingPathComponent("\(sha).json").path),
              let old = String(data: oldData, encoding: .utf8)
        else { return .contentMissing }
        let target = URL(fileURLWithPath: gameDir)
            .appendingPathComponent("Mods", isDirectory: true)
            .appendingPathComponent(mod.physicalFolderName, isDirectory: true)
            .appendingPathComponent("config.json")
        let loaded = fm.contents(atPath: target.path).flatMap { String(data: $0, encoding: .utf8) }

        do {
            _ = try backups.backUpConfigOncePerDay(for: mod, gameDir: gameDir)
        } catch {
            return .backupFailed(error.localizedDescription)
        }

        // Relecture juste avant d'écrire.
        let onDisk: ModConfigWriteGuard.DiskState
        if !fm.fileExists(atPath: target.path) {
            onDisk = .missing
        } else if let data = fm.contents(atPath: target.path), let text = String(data: data, encoding: .utf8) {
            onDisk = .content(text)
        } else {
            onDisk = .unreadable
        }
        switch ModConfigWriteGuard.decide(loaded: loaded, onDisk: onDisk, pending: old) {
        case .proceed: break
        case .externallyChanged, .unverifiable: return .changedOnDisk
        }
        // X7 : ouvrir les droits avant d'écrire dans le dossier du mod.
        ModZipInstaller.grantOwnerWriteAccess(in: target.deletingLastPathComponent())
        do {
            try old.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            return .writeFailed(error.localizedDescription)
        }
        return .reverted
    }
}
