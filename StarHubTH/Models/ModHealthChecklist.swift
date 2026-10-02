import Foundation

/// Le relevé en tête de l'onglet Santé d'une fiche : chaque vérification que
/// l'app sait faire sur un mod, avec son verdict — y compris ce qui n'a **pas**
/// pu être vérifié.
///
/// **Non mesuré n'est pas sain.** Sans rapport de raccourcis, ou pour un mod que
/// smapi.io ne connaît pas (deux tiers du parc), la ligne dit « non vérifié » :
/// une coche verte y mentirait. Ces lignes ne comptent pas dans les points à
/// regarder.
///
/// Ne calcule aucun signal : chaque entrée reçoit ce que la section voisine de
/// l'onglet affiche, lu par le même accesseur (`vm.anomaly(for:)`,
/// `compatibilityWarning`, `nexusPageState`…). Deux définitions d'un même
/// signal finiraient par faire dire « sain » à l'en-tête au-dessus d'une
/// section rouge.
enum ModHealthChecklist {
    enum Check: CaseIterable, Hashable {
        case security, loading, compatibility, log, conflicts, keybinds, performanceOverlap, nexusPage
    }

    /// Du plus bénin au plus grave : `max` donne le verdict.
    enum Status: Int, Comparable {
        case notApplicable, unmeasured, ok, info, warning, error
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
        /// Une ligne à regarder : elle mène à sa section.
        var needsAttention: Bool { self >= .info }
    }

    struct Entry: Equatable {
        let check: Check
        let status: Status
        /// Un compte à afficher (erreurs, conflits) ; `nil` quand la ligne n'en
        /// porte pas.
        let count: Int?
    }

    struct Inputs {
        var isMalicious = false
        var anomaly: ModAnomaly?
        /// Verdict smapi.io qui demande une décision (`compatibilityWarning`).
        var compatibilityWarning: ModCompatibility.Status?
        /// smapi.io connaît au moins un composant du mod.
        var knownToCompatibilityList = false
        var declaredConflicts = 0
        /// `nil` : aucun rapport de raccourcis n'a été produit.
        var keybindConflicts: Int?
        var performanceOverlaps = 0
        var nexusPage: NexusPageState?
        var hasNexusPage = false
    }

    static func entries(_ i: Inputs) -> [Entry] {
        Check.allCases.map { check in
            switch check {
            case .security:
                return Entry(check: check, status: i.isMalicious ? .error : .ok, count: nil)
            case .loading:
                return Entry(check: check, status: loadingStatus(i.anomaly), count: nil)
            case .compatibility:
                let status: Status
                if let warning = i.compatibilityWarning {
                    status = warning.severity >= ModCompatibility.Status.obsolete.severity ? .error : .warning
                } else {
                    status = i.knownToCompatibilityList ? .ok : .unmeasured
                }
                return Entry(check: check, status: status, count: nil)
            case .log:
                // Version installée seulement, comme la pastille de la liste.
                let errors = i.anomaly?.errorCount ?? 0, warnings = i.anomaly?.warningCount ?? 0
                let status: Status = errors > 0 ? .error : warnings > 0 ? .warning : .ok
                return Entry(check: check, status: status, count: errors + warnings > 0 ? errors + warnings : nil)
            case .conflicts:
                return Entry(check: check, status: i.declaredConflicts > 0 ? .warning : .ok,
                             count: i.declaredConflicts > 0 ? i.declaredConflicts : nil)
            case .keybinds:
                guard let n = i.keybindConflicts else { return Entry(check: check, status: .unmeasured, count: nil) }
                return Entry(check: check, status: n > 0 ? .warning : .ok, count: n > 0 ? n : nil)
            case .performanceOverlap:
                // Pas un conflit : le même travail fait deux fois. Information.
                return Entry(check: check, status: i.performanceOverlaps > 0 ? .info : .ok,
                             count: i.performanceOverlaps > 0 ? i.performanceOverlaps : nil)
            case .nexusPage:
                let status: Status
                switch i.nexusPage {
                case .removed?: status = .error
                case .unavailable?: status = .warning
                case nil: status = i.hasNexusPage ? .ok : .notApplicable
                }
                return Entry(check: check, status: status, count: nil)
            }
        }
    }

    /// Manifeste illisible ou dépendance manquante : le mod ne tourne pas.
    /// Deux copies actives : SMAPI en écarte une au hasard. Copies dormantes :
    /// rien ne casse aujourd'hui.
    private static func loadingStatus(_ anomaly: ModAnomaly?) -> Status {
        guard let anomaly else { return .ok }
        if anomaly.isUnloadable || anomaly.hasDependencyIssue { return .error }
        if let duplicate = anomaly.duplicate { return duplicate.isActive ? .warning : .info }
        return .ok
    }

    /// Le pire statut des lignes, et le nombre de lignes à regarder.
    static func verdict(_ entries: [Entry]) -> (status: Status, attention: Int) {
        (entries.map(\.status).max() ?? .ok, entries.filter { $0.status.needsAttention }.count)
    }
}
