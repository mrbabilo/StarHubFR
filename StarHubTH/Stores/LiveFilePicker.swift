import AppKit
import UniformTypeIdentifiers

/// L'implémentation réelle de `FilePicking` — AppKit, donc hors de Core
/// (`StarHubTHCore` ne peut pas l'importer, c'est le compilateur qui le
/// vérifie).
///
/// ⚠️ **`canChooseFiles` doit rester vrai.** Un bundle `.app` est un *file
/// package* : NSOpenPanel le traite comme un **fichier**, et le panneau
/// dossiers-seuls d'origine l'affichait donc grisé — impossible de désigner
/// `Stardew Valley.app`, alors que c'est ce que l'utilisateur voit. Restreint
/// aux applications (`UTType.application`), le filtre laisse les dossiers
/// ordinaires sélectionnables (`canChooseDirectories`) et grise le reste.
/// `treatsFilePackagesAsDirectories` reste au défaut : le forer changerait le
/// bouton « Ouvrir » en navigation et rendrait le `.app` de nouveau
/// insélectionnable. La descente jusqu'à `Contents/MacOS` est faite après
/// coup, par `GameDirLocator.normalize`.
struct LiveFilePicker: FilePicking {
    func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
