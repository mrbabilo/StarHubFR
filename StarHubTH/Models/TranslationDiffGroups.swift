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

        /// Le nom affiché : la section, préfixée du composant quand le mod en a
        /// plusieurs. `fallback` nomme les clés d'avant le premier commentaire,
        /// `orphan` les clés qui n'existent qu'en français.
        ///
        /// Partagé par l'en-tête du diff et la table des matières : sans quoi
        /// un mod à plusieurs dossiers `i18n` verrait deux sections homonymes
        /// de composants différents devenir indiscernables dans l'un des deux
        /// endroits mais pas l'autre.
        ///
        /// Les deux paramètres sont des `@autoclosure` : un seul des deux se
        /// résout jamais par groupe (`isOrphan` les rend mutuellement
        /// exclusifs), et l'appelant y loge une recherche localisée — l'évaluer
        /// systématiquement en doublerait le coût sur les 2056 en-têtes de
        /// `[CP] Ridgeside Village`.
        public func displayTitle(fallback: @autoclosure () -> String,
                                 orphan: @autoclosure () -> String) -> String {
            let section = isOrphan ? orphan() : (title ?? fallback())
            return component.map { "\($0) — \(section)" } ?? section
        }

        /// Le même groupe, restreint aux rangées retenues par un filtre.
        ///
        /// `id`, `title`, `component` et `firstKey` sont recopiés tels quels :
        /// ce sont des propriétés du **fichier**, pas du filtre en cours — les
        /// muter ferait sauter le repliage d'une section à l'autre à chaque
        /// frappe. Seuls `rows` et les comptes changent, puisque c'est ce que
        /// l'en-tête doit refléter. Rend `nil` si le filtre ne laisse aucune
        /// rangée : un groupe vide n'a rien à afficher.
        public func filtered(_ isIncluded: (DiffRow) -> Bool) -> DiffGroup? {
            let kept = rows.filter(isIncluded)
            guard !kept.isEmpty else { return nil }
            return DiffGroup(id: id, component: component, title: title,
                             firstKey: firstKey, rows: kept)
        }
    }

    /// Regroupe **toutes** les rangées d'un mod, en un seul passage — jamais un
    /// sous-ensemble déjà filtré : c'est `DiffGroup.filtered` qui applique le
    /// filtre en cours, sur des groupes dont l'identité a déjà été fixée une
    /// fois pour toutes ici. Sans quoi un filtre qui change fait et défait des
    /// groupes à chaque frappe, et l'état de repliage se retrouve à désigner
    /// une autre section.
    ///
    /// Les rangées arrivent dans l'ordre du fichier ; les comptes d'un groupe
    /// portent donc sur toutes ses rangées, filtre à part — c'est
    /// `DiffGroup.filtered` qui restreint l'affichage.
    public static func diffGroups(rows: [DiffRow]) -> [DiffGroup] {
        var groups: [DiffGroup] = []
        var currentRows: [DiffRow] = []
        var currentIdentity: String?
        // Combien de fois une identité de base a déjà été vue : une clé
        // dupliquée dans le fichier source (JSON à clés répétées, que le jeu
        // charge malgré tout) entrelace les rangs de section — 69, 77, 69,
        // 77… — et fait réapparaître un même rang dans un bloc non contigu
        // plus loin. Rien ne garantit que ce soit la seule cause possible :
        // l'unicité de l'identité ne doit donc pas dépendre de l'absence
        // d'un tel accident, elle doit être structurelle.
        var occurrences: [String: Int] = [:]

        func flush() {
            guard let first = currentRows.first else { return }
            let base = identity(of: first)
            let occurrence = (occurrences[base] ?? 0) + 1
            occurrences[base] = occurrence
            let id = occurrence == 1 ? base : "\(base)/\(occurrence)"
            groups.append(DiffGroup(id: id,
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

    /// L'identité **de base** d'une section : son composant, son rang, et le
    /// fait d'être orpheline. Deux occurrences non contiguës de la même
    /// identité de base reçoivent un suffixe dans `diffGroups` — voir
    /// `occurrences` ci-dessus — mais cette fonction ne rend que la part
    /// commune aux deux.
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
