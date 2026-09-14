import AppKit
import UniformTypeIdentifiers

/// L'implémentation réelle d'`ImagePicking` — AppKit, donc hors de Core
/// (`StarHubTHCore` ne peut pas l'importer, c'est le compilateur qui le
/// vérifie). La configuration du panneau est celle que `selectCustomAvatar`
/// posait en ligne : trois formats d'image, un seul fichier, pas de dossier.
struct LiveImagePicker: ImagePicking {
    func pickImage(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = title
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
