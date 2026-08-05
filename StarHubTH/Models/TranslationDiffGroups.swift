import Foundation

/// Le regroupement des rangées du diff par section de l'auteur.
///
/// Séparé de `TranslationCoverage` parce que c'en est un consommateur, pas un
/// rouage : la couverture se calcule sans savoir comment on l'affichera.
///
/// **Une section s'identifie par son rang, jamais par son titre.**
/// `[CP] Ridgeside Village` porte 65 sections « Spring », 1407 de ses 2056
/// titres sont des doublons. Une identité par titre replierait les 65 d'un
/// coup, ferait atterrir la navigation sur la première, et donnerait à SwiftUI
/// des identités dupliquées dans un `ForEach` — donc des rangées perdues.
extension TranslationCoverage {
    public struct DiffGroup: Identifiable, Equatable, Sendable {
        /// Composant et rang : stable, unique, et indépendant du titre.
        public let id: String
        public let component: String?
        /// Le titre écrit par l'auteur, `nil` pour les clés qui précèdent tout
        /// commentaire.
        public let title: String?
        /// La première clé du groupe. C'est ce qui distingue deux sections
        /// homonymes dans la table des matières.
        public let firstKey: String
        public let rows: [DiffRow]
        public let counts: [DiffRow.State: Int]
        /// Le bloc des clés qui n'existent qu'en français. Il n'a pas de titre,
        /// mais ce n'est pas pour la même raison que les clés d'avant le premier
        /// commentaire : la vue doit les nommer différemment.
        public let isOrphan: Bool

        public init(id: String, component: String?, title: String?,
                    firstKey: String, rows: [DiffRow]) {
            self.id = id
            self.component = component
            self.title = title
            self.firstKey = firstKey
            self.rows = rows
            self.counts = rows.reduce(into: [:]) { $0[$1.state, default: 0] += 1 }
            self.isOrphan = rows.first?.state == .orphan
        }

        public func remaining(_ state: DiffRow.State) -> Int { counts[state] ?? 0 }
    }

    /// Regroupe des rangées **déjà filtrées**, dans l'ordre où elles arrivent —
    /// celui du fichier. Les comptes portent donc sur ce qui est visible : un
    /// en-tête annonçant 12 au-dessus de 3 lignes mentirait.
    public static func diffGroups(rows: [DiffRow]) -> [DiffGroup] {
        var groups: [DiffGroup] = []
        var currentRows: [DiffRow] = []
        var currentIdentity: String?

        func flush() {
            guard let first = currentRows.first else { return }
            groups.append(DiffGroup(id: identity(of: first),
                                    component: first.component,
                                    title: first.section,
                                    firstKey: first.key,
                                    rows: currentRows))
            currentRows = []
        }

        for row in rows {
            let identityOfRow = identity(of: row)
            if identityOfRow != currentIdentity {
                flush()
                currentIdentity = identityOfRow
            }
            currentRows.append(row)
        }
        flush()
        return groups
    }

    /// L'identité d'une section : son composant, son rang, et le fait d'être
    /// orpheline.
    ///
    /// Les rangs de deux composants se recouvrent — chacun repart de 0 — d'où
    /// le composant. Et **deux** blocs de rangées n'ont aucun rang : les clés
    /// d'avant le premier commentaire, en tête du tableau, et les orphelines
    /// que `diffRows` ajoute en queue. Sans le troisième terme, ces deux blocs
    /// disjoints partageraient une identité.
    ///
    /// L'identité n'est jamais positionnelle : les positions bougent à chaque
    /// filtre, et l'état de repliage désignerait alors une autre section à
    /// chaque frappe.
    private static func identity(of row: DiffRow) -> String {
        let rank = row.state == .orphan ? "orphan" : (row.sectionIndex.map(String.init) ?? "-")
        return "\(row.component ?? "")#\(rank)"
    }
}
