import AppKit
import SwiftUI

/// Un texte en lecture seule, sélectionnable **et** dont la sélection se lit.
///
/// SwiftUI sait rendre un texte sélectionnable (`.textSelection(.enabled)`)
/// mais pas dire ce qui est sélectionné : l'API n'existe qu'à partir de
/// macOS 15, et l'application vise macOS 14. D'où ce pont AppKit, calqué sur
/// `CodeEditorView` — le seul autre du dépôt.
///
/// **Hauteur fixe, et volontairement.** Le texte source va d'un mot à un
/// dialogue de dix lignes ; laisser le bloc grandir ferait sauter le champ de
/// saisie d'une clé à l'autre, exactement ce que l'en-tête de
/// `TranslationEditorView` interdit. Ce qui dépasse défile.
struct SelectableTextView: NSViewRepresentable {
    let text: String
    /// Ce qui est sélectionné à cet instant, remonté à la vue SwiftUI.
    @Binding var selection: String
    /// L'entrée ajoutée au menu contextuel, et ce qu'elle déclenche. Un titre
    /// vide n'ajoute rien : le menu reste celui d'AppKit.
    let actionTitle: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Ne réécrire que sur changement : réaffecter `string` remet la
        // sélection à zéro, et le faire à chaque passe de rendu la ferait
        // disparaître sous le curseur de l'utilisateur.
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableTextView

        init(_ parent: SelectableTextView) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let selected = range.length > 0
                ? (textView.string as NSString).substring(with: range)
                : ""
            guard selected != parent.selection else { return }
            // Hors de la passe de rendu en cours : écrire un `@State` pendant
            // que SwiftUI dessine est un avertissement d'exécution, et le
            // changement de sélection arrive au milieu du layout d'AppKit.
            Task { @MainActor [parent] in
                parent.selection = selected
            }
        }

        func textView(_ view: NSTextView, menu: NSMenu,
                      for event: NSEvent, at charIndex: Int) -> NSMenu? {
            guard !parent.actionTitle.isEmpty, view.selectedRange().length > 0 else {
                return menu
            }
            let item = NSMenuItem(title: parent.actionTitle,
                                  action: #selector(runAction), keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            return menu
        }

        @objc private func runAction() {
            parent.action()
        }
    }
}
