import Foundation

/// Ce que le service de plan rend à la feuille : des valeurs typées, jamais
/// du texte — la feuille (Task 6) les traduit. Un refus et un saut se disent
/// toujours, avec le mod qu'ils concernent.
extension KeybindPlanService {

    /// Pourquoi une opération entière est refusée.
    enum Failure: Equatable, Sendable {
        /// Aucun plan prêt (jamais calculé, ou déjà appliqué : recalculer).
        case noPlan
        /// Jeu ouvert : un mod C# réécrit sa config quand il veut. Ce refus
        /// passe par `refusal` et garde le plan prêt.
        case gameRunning
        /// Le rapport a changé depuis le calcul : recalculer.
        case stalePlan
        case noGameDir
        /// La sauvegarde a échoué : rien n'a été écrit. Porte le message système.
        case backupFailed(String)
        case nothingToUndo
        /// Un lot plus récent a suivi le plan : restaurer depuis l'écran des
        /// sauvegardes.
        case notLatestBackup
        /// La restauration a levé. Porte le message système.
        case restoreFailed(String)
    }

    /// Un mod laissé tel quel, et pourquoi.
    struct Skip: Equatable, Sendable {
        /// `Error` pour servir d'échec à `Result` dans la réécriture d'un fichier.
        enum Reason: Error, Equatable {
            /// Aucun mod de ce dossier dans le parc.
            case modNotFound
            /// Mis en pause depuis le calcul.
            case paused
            /// Le lot ne porte pas son `config.json` (dossier lié par symlink,
            /// fichier disparu avant la sauvegarde) : jamais écrit sans copie.
            case noBackupCopy
            /// `config.json` disparu : jamais recréé.
            case missing
            /// `config.json` présent mais illisible en UTF-8.
            case unreadable
            /// Le texte sauvegardé ne se réécrit pas (réglage ou touche
            /// disparus, JSON invalide…).
            case writerFailed(KeybindPlanWriter.Failure, keyPath: [String])
            /// Le fichier a bougé entre la sauvegarde et l'écriture.
            case externallyChanged
            /// L'écriture a levé. Porte le message système.
            case writeFailed(String)
            /// Annulation : le fichier a été modifié depuis le plan — la
            /// modification est gardée.
            case changedSinceApply
            /// Annulation : la restauration de ce fichier a échoué.
            case restoreFailed
        }
        let folderName: String
        let reason: Reason
    }

    struct AppliedResult: Equatable, Sendable {
        let written: Int
        let skipped: [Skip]
        /// Le lot de `ModConfigBackupManager` qui rend l'état d'avant plan.
        let backupId: String?
    }

    struct UndoResult: Equatable, Sendable {
        let restored: Int
        let skipped: [Skip]
    }

    enum State: Equatable {
        case idle, computing, ready(KeybindPlan), applying, applied(AppliedResult),
             undone(UndoResult), failed(Failure)
    }
}
