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
