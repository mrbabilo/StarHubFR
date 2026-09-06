import Testing
import Foundation
@testable import StarHubTHCore

/// **X77 — le seul marqueur fiable de présence de SMAPI : `smapi-internal/`.**
///
/// Mesuré le 2026-09-06 sur une installation de contrôle du vrai binaire
/// 4.5.2 : `smapi-internal/` est posé par **chaque** installation et retiré
/// par **chaque** désinstallation. `StardewValley-original`, lui, n'apparaît
/// qu'en **remplaçant** une installation SMAPI antérieure — une installation
/// propre sur un jeu vierge ne le pose jamais. Détecter SMAPI par lui faisait
/// une installation réussie passer pour absente au scan suivant.
@Suite struct SmapiInstallMarkerTests {

    private func withTempGameDir(_ body: (String) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmapiInstallMarkerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.path)
    }

    @Test func aCleanInstallIsDetected() throws {
        try withTempGameDir { gameDir in
            let internalDir = (gameDir as NSString)
                .appendingPathComponent(SmapiInstallMarker.folderName)
            try FileManager.default.createDirectory(atPath: internalDir, withIntermediateDirectories: true)

            #expect(SmapiInstallMarker.isPresent(gameDir: gameDir))
        }
    }

    @Test func aFolderWithoutTheInternalFolderIsNotInstalled() throws {
        try withTempGameDir { gameDir in
            #expect(!SmapiInstallMarker.isPresent(gameDir: gameDir))
        }
    }

    @Test func theLegacyOriginalBackupAloneDoesNotCount() throws {
        // La règle neuve, épinglée contre l'ancienne : `StardewValley-original`
        // ne prouve rien. Une désinstallation propre le laisse éventuellement
        // derrière elle — SMAPI n'est plus là pour autant.
        try withTempGameDir { gameDir in
            let legacy = (gameDir as NSString).appendingPathComponent("StardewValley-original")
            try "#!/bin/sh".write(toFile: legacy, atomically: true, encoding: .utf8)

            #expect(!SmapiInstallMarker.isPresent(gameDir: gameDir))
        }
    }

    @Test func aStrayFileNamedLikeTheFolderDoesNotCount() throws {
        // `smapi-internal` est un **dossier** ; un fichier accidentel du même
        // nom (résidu d'extraction ratée) n'est pas une installation.
        try withTempGameDir { gameDir in
            let stray = (gameDir as NSString).appendingPathComponent(SmapiInstallMarker.folderName)
            try "not a directory".write(toFile: stray, atomically: true, encoding: .utf8)

            #expect(!SmapiInstallMarker.isPresent(gameDir: gameDir))
        }
    }
}
