import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// L'application de bureau DeepL, si elle est là.
///
/// Elle ne remplace pas la clé d'API et ne peut pas : relevé le 2026-08-21 sur
/// une installation réelle (v26.6), elle ne déclare aucun schéma d'URL et
/// n'ouvre aucun port en écoute — il n'y a rien à quoi se brancher. La
/// détection ne sert donc qu'à le **dire**, pour épargner à qui l'a installée
/// de chercher pourquoi l'application lui demande encore une clé.
public enum DeepLDesktop {
    /// Relevé sur `/Applications/DeepL.app` : l'identifiant porte encore le
    /// nom du produit d'origine, il ne se devine pas depuis « DeepL ».
    public static let bundleIdentifier = "com.linguee.DeepLCopyTranslator"

    /// La page où DeepL montre la clé d'API — celle que sa propre
    /// documentation nomme. Sans session, elle mène à la connexion, d'où
    /// l'inscription gratuite est accessible.
    public static let apiKeyPageURL = URL(string: "https://www.deepl.com/your-account/keys")!

    /// `true` seulement quand la résolution **aboutit**. Un `nil` ne prouve
    /// pas l'absence — LaunchServices peut être en retard, l'application
    /// vivre hors de `/Applications` —, et c'est pourquoi l'appelant se tait
    /// dans ce cas plutôt que d'annoncer une absence qu'il ne sait pas.
    public static func isInstalled(
        resolve: (String) -> URL? = defaultResolve
    ) -> Bool {
        resolve(bundleIdentifier) != nil
    }

    /// La résolution réelle, par LaunchServices.
    public static let defaultResolve: (String) -> URL? = { identifier in
        #if canImport(AppKit)
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        #else
        nil
        #endif
    }
}
