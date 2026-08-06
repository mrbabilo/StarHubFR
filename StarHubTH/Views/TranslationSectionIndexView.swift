import SwiftUI

/// La table des matières des sections d'un diff.
///
/// Un popover, pas une colonne : la zone défilante du diff est plafonnée à
/// 460 pt dans un onglet de fiche, une colonne latérale n'aurait pas de place.
///
/// Chaque ligne montre le titre **et la première clé de la section**. Sans cette
/// seconde ligne, la table des matières de `[CP] Ridgeside Village` serait des
/// dizaines de lignes « Spring » indiscernables — sur ses 1861 sections
/// titrées (mesuré via `diffGroups`, pas les 2065 lignes de commentaire brutes
/// du fichier : ce dernier chiffre compte autre chose, voir `I18nOutline`).
///
/// La liste est paresseuse : jusqu'à 1862 lignes (tous les groupes de
/// `[CP] Ridgeside Village`, bloc sans titre et orphelin compris) ne se
/// rendent pas d'un bloc.
struct TranslationSectionIndexView: View {
    let groups: [TranslationCoverage.DiffGroup]
    let searchPlaceholder: String
    let noMatchLabel: String
    let untitledLabel: String
    /// Les clés qui n'existent qu'en français : sans titre, mais pas au même
    /// titre que celles d'avant le premier commentaire.
    let orphanLabel: String
    let onSelect: (TranslationCoverage.DiffGroup) -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(searchPlaceholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.top, 10)
            Divider()
            if matches.isEmpty {
                Text(noMatchLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(matches) { group in
                            row(group)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 400)
    }

    private func row(_ group: TranslationCoverage.DiffGroup) -> some View {
        Button {
            onSelect(group)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    // Même règle de préfixe que l'en-tête (`DiffGroup.displayTitle`) :
                    // sans le composant, deux sections homonymes de composants
                    // différents seraient indiscernables ici, sauf par leur
                    // première clé.
                    Text(group.displayTitle(fallback: untitledLabel, orphan: orphanLabel))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    // Ce qui distingue deux sections homonymes du même composant.
                    Text(group.firstKey)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                RemainderBadges(group: group, spacing: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var matches: [TranslationCoverage.DiffGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return groups }
        // Sur `displayTitle`, pas le `title` brut : c'est ce que `row(_:)`
        // affiche juste en dessous, préfixe de composant et libellés « Orpheline »
        // / « Avant la première section » compris. Filtrer sur le titre brut
        // laisserait lire une ligne sans pouvoir la retrouver par ce qu'elle montre.
        return groups.filter {
            $0.displayTitle(fallback: untitledLabel, orphan: orphanLabel)
                .lowercased().contains(needle)
                || $0.firstKey.lowercased().contains(needle)
        }
    }
}
