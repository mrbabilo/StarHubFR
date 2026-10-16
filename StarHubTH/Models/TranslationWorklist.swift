import Foundation

/// Un mod dont la traduction française est commencée mais pas finie.
struct TranslationWorkItem: Identifiable, Equatable, Sendable {
    var id: String { folderName }
    let folderName: String
    let name: String
    let isEnabled: Bool
    /// `nil` tant que la passe de couverture n'a pas lu le mod (un mod
    /// « à revoir » par la date seule peut ne pas encore l'être).
    let coverage: TranslationCoverage.Coverage?
    /// L'anglais a bougé depuis la traduction : date des fichiers, ou clés
    /// obsolètes connues du dernier diff.
    let isStale: Bool
    let outdatedKeys: Int

    var missingCount: Int { coverage.map { max(0, $0.total - $0.translated) } ?? 0 }
    /// La part qui reste, de 0 à 1 (0 sans mesure).
    var remainingShare: Double {
        guard let coverage, coverage.total > 0 else { return 0 }
        return Double(missingCount) / Double(coverage.total)
    }
}

/// R3 (audit UX du 2026-10-16) — la liste « À finir » de la page Traductions
/// FR : ce qui reste à traduire sur **tout le parc**, en pause compris.
///
/// **Mêmes prédicats que la liste des mods**, par construction : un mod y
/// figure s'il passe le filtre « Partiellement traduits » ou « À revoir »
/// (`ModListScoping.matchesTranslation`), au même grain (le mod de premier
/// niveau, un pack par son en-tête ou l'un de ses composants). Réécrire ces
/// règles ici aurait fait diverger deux comptes que l'utilisateur compare.
///
/// Les mods sans français (« À traduire ») n'y sont pas : la passe de
/// couverture ne lit que les mods qui ont un `fr` (`FrenchCoveragePass`), et
/// les lister à 0 % ferait surgir des centaines de lignes. La page les compte
/// et renvoie vers la recherche Nexus.
enum TranslationWorklist {

    static func items(in mods: [ModItem],
                      state: ModListScoping.TranslationState) -> [TranslationWorkItem] {
        mods.filter {
            ModListScoping.matchesTranslation($0, .partial, state: state)
                || ModListScoping.matchesTranslation($0, .stale, state: state)
        }
        .map { mod in
            TranslationWorkItem(
                folderName: mod.folderName, name: mod.name, isEnabled: mod.isEnabled,
                coverage: state.coverage[mod.folderName],
                isStale: ModListScoping.matchesTranslation(mod, .stale, state: state),
                outdatedKeys: state.outdatedKeys[mod.folderName] ?? 0)
        }
        .sorted(by: Order.remainingKeys.precedes)
    }

    /// L'ordre choisi dans la page (remarque de l'auteur, 2026-10-16 : un
    /// tri par clés seul ne se lisait pas comme un tri).
    enum Order: String, CaseIterable, Sendable {
        case remainingKeys, remainingPercent, name

        func precedes(_ a: TranslationWorkItem, _ b: TranslationWorkItem) -> Bool {
            switch self {
            case .remainingKeys:
                // Même tri que la section du diagnostic de profil (le plus gros
                // reste d'abord) ; un mod complet mais « à revoir » (reste 0) se
                // départage par ses clés obsolètes avant le nom.
                guard a.missingCount == b.missingCount, a.outdatedKeys != b.outdatedKeys else {
                    return ProfileTranslationCoverage.precedes(missing: a.missingCount, name: a.name,
                                                               missing: b.missingCount, name: b.name)
                }
                return a.outdatedKeys > b.outdatedKeys
            case .remainingPercent:
                let (ra, rb) = (a.remainingShare, b.remainingShare)
                return ra != rb ? ra > rb : Order.remainingKeys.precedes(a, b)
            case .name:
                let order = a.name.localizedStandardCompare(b.name)
                return order != .orderedSame ? order == .orderedAscending : a.folderName < b.folderName
            }
        }
    }

    /// Les mods traduisibles sans aucun français — le renvoi vers Nexus.
    static func untranslatedCount(in mods: [ModItem], state: ModListScoping.TranslationState) -> Int {
        mods.filter { ModListScoping.matchesTranslation($0, .missing, state: state) }.count
    }

    /// Les mods à français que la passe n'a pas encore lus : tant qu'il en
    /// reste, une liste vide ne veut pas dire « rien à finir ».
    static func unmeasuredCount(in mods: [ModItem], pass: FrenchCoveragePass.State) -> Int {
        FrenchCoveragePass.targets(in: mods, known: Set(pass.coverage.keys).union(pass.unmeasurable)).count
    }
}
