import Foundation

/// Plan de raccourcis — la phrase de chaque valeur typée du service et du
/// solveur. `switch` exhaustifs, sans `default` : une raison ajoutée en amont
/// ne compile plus tant qu'elle n'a pas sa phrase — jamais de refus muet.
/// Une raison qui porte un message système le met après le préfixe traduit
/// (`%@` en fin de clé : la typographie suit la langue).
///
/// `localize` plutôt qu'un `LocalizationStore` : la vue passe
/// `localization.L`, et ces fonctions restent pures.
enum KeybindPlanText {
    typealias Localize = (String) -> String

    static func family(_ family: KeybindFamily?, _ localize: Localize) -> String {
        switch family {
        case .action: localize(L10n.KeybindPlan.familyAction)
        case .info: localize(L10n.KeybindPlan.familyInfo)
        case .rare: localize(L10n.KeybindPlan.familyRare)
        case nil: localize(L10n.KeybindPlan.familyNone)
        }
    }

    /// Le motif d'un déplacement, sous le réglage.
    static func why(_ reason: PlannedMove.Reason, _ localize: Localize) -> String {
        switch reason {
        case .conflictLoser(let keeper): String(format: localize(L10n.KeybindPlan.whyConflict), keeper)
        case .familyPlacement: localize(L10n.KeybindPlan.whyFamily)
        }
    }

    static func unmovable(_ reason: UnmovableSetting.Reason, _ localize: Localize) -> String {
        switch reason {
        case .noFamily: localize(L10n.KeybindPlan.reasonNoFamily)
        case .authorBlock: localize(L10n.KeybindPlan.reasonAuthorBlock)
        case .remapMod: localize(L10n.KeybindPlan.reasonRemapMod)
        case .heldModifier: localize(L10n.KeybindPlan.reasonHeldModifier)
        case .inert: localize(L10n.KeybindPlan.reasonInert)
        case .contextResolved: localize(L10n.KeybindPlan.reasonContextResolved)
        case .familyFull: localize(L10n.KeybindPlan.reasonFamilyFull)
        case .singleButtonFieldFull: localize(L10n.KeybindPlan.reasonSingleButtonFieldFull)
        }
    }

    /// Un mod sauté : son nom (le dossier à défaut), puis la raison.
    static func skip(_ skip: KeybindPlanService.Skip, name: String, _ localize: Localize) -> String {
        String(format: localize(L10n.KeybindPlan.skippedItem), name, reason(skip.reason, localize))
    }

    static func reason(_ reason: KeybindPlanService.Skip.Reason, _ localize: Localize) -> String {
        switch reason {
        case .modNotFound: localize(L10n.KeybindPlan.skipModNotFound)
        case .paused: localize(L10n.KeybindPlan.skipPaused)
        case .noBackupCopy: localize(L10n.KeybindPlan.skipNoBackupCopy)
        case .missing: localize(L10n.KeybindPlan.skipMissing)
        case .unreadable: localize(L10n.KeybindPlan.skipUnreadable)
        case .writerFailed(let failure, let keyPath):
            String(format: localize(writerKey(failure)), keyPath.joined(separator: "."))
        case .externallyChanged: localize(L10n.KeybindPlan.skipExternallyChanged)
        case .writeFailed(let message): String(format: localize(L10n.KeybindPlan.skipWriteFailed), message)
        case .changedSinceApply: localize(L10n.KeybindPlan.skipChangedSinceApply)
        case .restoreFailed: localize(L10n.KeybindPlan.skipRestoreFailed)
        }
    }

    private static func writerKey(_ failure: KeybindPlanWriter.Failure) -> String {
        switch failure {
        case .unreadable: L10n.KeybindPlan.skipWriterUnreadable
        case .pathMissing: L10n.KeybindPlan.skipWriterPathMissing
        case .alternativeMissing: L10n.KeybindPlan.skipWriterAlternativeMissing
        case .unsupportedValue: L10n.KeybindPlan.skipWriterUnsupportedValue
        }
    }

    static func failure(_ failure: KeybindPlanService.Failure, _ localize: Localize) -> String {
        switch failure {
        case .noPlan: localize(L10n.KeybindPlan.failureNoPlan)
        case .gameRunning: localize(L10n.KeybindPlan.failureGameRunning)
        case .stalePlan: localize(L10n.KeybindPlan.failureStalePlan)
        case .noGameDir: localize(L10n.KeybindPlan.failureNoGameDir)
        case .backupFailed(let message): String(format: localize(L10n.KeybindPlan.failureBackupFailed), message)
        case .nothingToUndo: localize(L10n.KeybindPlan.failureNothingToUndo)
        case .notLatestBackup: localize(L10n.KeybindPlan.failureNotLatestBackup)
        case .restoreFailed(let message): String(format: localize(L10n.KeybindPlan.failureRestoreFailed), message)
        }
    }
}
