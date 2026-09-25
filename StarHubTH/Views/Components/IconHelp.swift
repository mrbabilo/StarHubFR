import SwiftUI

extension View {
    /// L'infobulle **et** le libellé VoiceOver d'un bouton à icône seule.
    ///
    /// Sur macOS, `.help` ne pose que l'aide d'accessibilité : sans libellé,
    /// VoiceOver lit le nom du symbole (« xmark circle fill ») ou rien. Le
    /// relevé du 2026-09-25 (I-T3) en comptait 31. Un bouton à icône seule
    /// passe donc par ce modificateur plutôt que par `.help`.
    func iconHelp(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}
