import Foundation

/// R2 (audit UX 2026-10-16) — le journal SMAPI dont dérivent les lignes des
/// Alertes et la carte Santé, dit de la même façon des deux côtés : sa date,
/// et son âge quand il est périmé (écrit avant la session de l'app, voir
/// `StarHubTHViewModel.smapiLogStale`).
///
/// Les deux formats suivent la **langue de l'app** (`locale`), pas celle du
/// système : `Text(date, style: .relative)` du badge « Log périmé » parlait
/// anglais dans une interface française.
struct SmapiLogSource: Equatable {
    /// « 14/10/2026 17:13 » : date et heure courtes.
    let date: String
    /// « 1 j 18 h » quand le journal est périmé, `nil` sinon. Deux unités au
    /// plus : l'heure près suffit à dire « d'avant-hier ».
    let staleAge: String?

    /// `nil` sans journal lu : aucune date ne s'invente. Les Alertes peuvent
    /// exister sans lui (raccourcis, conflits) ; la ligne disparaît alors.
    init?(logDate: Date?, isStale: Bool, now: Date = .init(), locale: Locale) {
        guard let logDate else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        date = dateFormatter.string(from: logDate)
        staleAge = isStale ? Self.age(from: logDate, to: now, locale: locale) : nil
    }

    private static func age(from start: Date, to end: Date, locale: Locale) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        // Un journal d'il y a 30 s reste « périmé » s'il précède la session ;
        // « 0 min » serait faux, une minute est le plancher lisible.
        return formatter.string(from: max(end.timeIntervalSince(start), 60))
    }
}
