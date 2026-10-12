import Foundation

public extension ProbePerformanceActions {
    /// Défait un `revertConfig` (mesure pilotée, M7) : remet le `config.json`
    /// d'avant — ou le retire s'il n'existait pas — **seulement** si le disque
    /// porte encore ce que le revert a écrit (`configs/<sha>.json`), jeu fermé,
    /// droits ouverts d'abord (X7). Contenus jamais journalisés.
    static func undoRevertConfig(at target: URL, previous: String?, revertedToSha sha: String,
                                 configsDirectory: URL, gameRunning: Bool) -> RevertOutcome {
        guard !gameRunning else { return .gameRunning }
        let fm = FileManager.default
        guard !sha.isEmpty, sha.allSatisfy(\.isHexDigit),
              let writtenData = fm.contents(atPath: configsDirectory.appendingPathComponent("\(sha).json").path),
              let written = String(data: writtenData, encoding: .utf8)
        else { return .contentMissing }
        guard let data = fm.contents(atPath: target.path), String(data: data, encoding: .utf8) == written
        else { return .changedOnDisk }
        ModZipInstaller.grantOwnerWriteAccess(in: target.deletingLastPathComponent())
        do {
            if let previous {
                try previous.write(to: target, atomically: true, encoding: .utf8)
            } else {
                try fm.removeItem(at: target)
            }
        } catch {
            return .writeFailed(error.localizedDescription)
        }
        return .reverted
    }
}
