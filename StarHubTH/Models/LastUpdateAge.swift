import Foundation

/// B2-T5 — l'âge de la dernière mise à jour Nexus d'un mod, affiché à côté de
/// sa date sur la fiche.
///
/// La règle est le **seuil d'un an révolu** : en deçà, la date se lit fraîche
/// d'elle-même et l'âge serait du bruit ; au-delà, il devient le signal —
/// « ce mod dort depuis cinq ans ». Le texte vient de
/// `RelativeDateTimeFormatter`, dont le rendu a été vérifié sur la machine de
/// référence (« il y a 5 ans », « 5 years ago ») : pas de clé L10n à tenir,
/// la localisation suit la locale du système.
enum LastUpdateAge {
    /// Une année moyenne — 365,25 jours, bissextiles compris. La frontière
    /// exacte d'une année civile n'apporterait rien : l'âge se compte en
    /// années, pas au jour près.
    private static let oneYear: TimeInterval = 365.25 * 86_400

    /// L'âge de `date` vu de `now`, ou `nil` tant qu'un an n'est pas révolu.
    /// `locale` n'existe que pour les tests ; par défaut elle suit le système
    /// (`autoupdatingCurrent`), comme `L()` suit le changement de langue en
    /// cours de session.
    static func ageText(for date: Date, now: Date = .init(),
                        locale: Locale = .autoupdatingCurrent) -> String? {
        guard now.timeIntervalSince(date) >= oneYear else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
