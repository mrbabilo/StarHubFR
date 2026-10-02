import Foundation

enum ZipStructure: Equatable {
    case singleMod(folderName: String)
    case multiMod(mods: [String])
    case flatRoot
    case unrecognized
    /// A1-T5 — le seul manifeste vit à l'intérieur d'un bundle `.app`
    /// (`X.app/Contents/Resources/CompanionMod`) : le vrai produit de
    /// l'archive est l'application, le mod n'est qu'une pièce.
    case modEmbeddedInAppBundle(modPath: String, appPath: String)
}

enum InstallError: LocalizedError {
    case extractionFailed(String)
    case unsafeContent
    case gameDirEmpty
    case backupFailed(String)
    case installFailed(String)
    case rarToolMissing

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let detail): return "Failed to extract archive file: \(detail)"
        case .unsafeContent: return "This archive contains unsafe content (symbolic links) and was rejected."
        case .gameDirEmpty: return "Game directory is not set."
        case .backupFailed(let reason): return "Backup of the existing mod failed, installation aborted: \(reason)"
        case .installFailed(let reason): return "Installation failed: \(reason)"
        case .rarToolMissing: return "RAR extraction requires 'unrar', 'unar', or '7z' (install via Homebrew: brew install unrar)."
        }
    }

    /// B2-T4 : commande copiable, alignée sur le message et l'accueil :
    /// `unar`, un seul conseil.
    var copyableCommand: String? {
        switch self {
        case .rarToolMissing: return "brew install unar"
        default: return nil
        }
    }
}
