import Foundation

/// D4-T7 — ce que `ConfigEditorModel` prend à la capture GMCM de la sonde,
/// dans quel ordre. À part de `ConfigEditorModel.swift`, déjà au-delà de
/// 400 lignes (taille verrouillée par le cliquet).
extension ConfigEditorModel {
    /// GMCM passe avant l'i18n quand la capture est dans la langue de l'app :
    /// c'est alors exactement ce que le jeu montre (87 libellés du parc où
    /// l'i18n dit autre chose — anglais, ou autre option).
    static func gmcmFirst(_ gmcm: GmcmModOptions?, appLanguage: String?) -> Bool {
        guard let captured = gmcm?.language, let appLanguage else { return false }
        return captured.lowercased() == appLanguage.lowercased()
    }

    /// Libellé ou description : le schéma d'abord (un `Name` explicite de
    /// pack), puis i18n et GMCM dans l'ordre que dicte la langue.
    static func pickText(schema: String?, i18n: String?, gmcm: String?, gmcmFirst: Bool) -> String? {
        if let schema { return schema }
        let i18n = i18n.flatMap { $0.isEmpty ? nil : $0 }
        return gmcmFirst ? (gmcm ?? i18n) : (i18n ?? gmcm)
    }

    /// Les bornes ne vont qu'à un champ chiffré : un contrôle devenu menu ou
    /// raccourci n'a pas de curseur.
    static func gmcmBounds(for control: Control, entry: GmcmModOptions.Entry?) -> GmcmModOptions.Bounds? {
        switch control {
        case .integer, .decimal: return entry?.bounds
        case .toggle, .text, .choice, .keybind: return nil
        }
    }
}
