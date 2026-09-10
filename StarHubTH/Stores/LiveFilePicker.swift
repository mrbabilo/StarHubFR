import AppKit

/// L'implémentation réelle de `FilePicking` — AppKit, donc hors de Core
/// (`StarHubTHCore` ne peut pas l'importer, c'est le compilateur qui le
/// vérifie). La configuration du panneau est celle que `selectGameDir`
/// posait en ligne : dossiers seuls, sélection unique.
struct LiveFilePicker: FilePicking {
    func pickDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
