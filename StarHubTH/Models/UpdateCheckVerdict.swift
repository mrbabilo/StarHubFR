import Foundation

/// Ce que la page Mises à jour peut **affirmer** d'un compte : un zéro ne
/// vaut « tout est à jour » que si une passe complète l'a mesuré.
///
/// Trois zéros se ressemblent et ne disent pas la même chose :
///
/// - **jamais vérifié** — aucune passe smapi.io n'a abouti
///   (`nexusUpdatesLastCheckedAt` absent) : le zéro n'a rien mesuré ;
/// - **vérifiables à jour** — la passe a abouti, mais des mods sont restés
///   sans verdict, **ou** on ne sait pas s'il y en avait : la liste des
///   invérifiables n'est pas persistée, une relance la remet à vide sans
///   qu'elle le soit ;
/// - **tout est à jour** — passe complète **dans cette session**, aucun
///   invérifiable.
///
/// L'horodatage accompagne les deux derniers : « à jour » d'il y a trois
/// jours n'est pas « à jour » de ce matin, et c'est au lecteur d'en juger —
/// pas de seuil de péremption inventé ici.
public enum UpdateCheckVerdict: Equatable, Sendable {
    case pending(Int)
    case upToDate(checkedAt: Date)
    case verifiableUpToDate(checkedAt: Date)
    case neverChecked

    /// - Parameters:
    ///   - pending: le compte affiché (badge, ou la seule section Nexus).
    ///   - lastCheckedAt: la dernière passe **complète**, toutes sessions.
    ///   - unverifiableCount: les mods sans verdict de la dernière passe
    ///     complète de cette session ; `nil` quand on ne le sait pas
    ///     (relance, ou passe en cours qui l'a remis en question).
    public static func resolve(pending: Int, lastCheckedAt: Date?,
                               unverifiableCount: Int?) -> UpdateCheckVerdict {
        if pending > 0 { return .pending(pending) }
        guard let checkedAt = lastCheckedAt else { return .neverChecked }
        return unverifiableCount == 0
            ? .upToDate(checkedAt: checkedAt)
            : .verifiableUpToDate(checkedAt: checkedAt)
    }

    /// « il y a 3 heures », « hier » — dans la langue de l'interface, pas
    /// celle du système : la phrase qui l'entoure vient de `L()`. Une date
    /// dans le futur (horloge reculée) se lit « maintenant » plutôt que
    /// « dans 2 minutes ».
    public static func ageText(since date: Date, now: Date = .init(),
                               locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }
}
