import SwiftUI

/// La table des matières des sections d'un diff.
///
/// Un popover, pas une colonne : la zone défilante du diff est plafonnée à
/// 460 pt dans un onglet de fiche, une colonne latérale n'aurait pas de place.
///
/// Chaque ligne montre le titre **et la première clé de la section**. Sans cette
/// seconde ligne, la table des matières de `[CP] Ridgeside Village` serait 65
/// lignes « Spring » indiscernables — ses 2056 titres comptent 1407 doublons.
///
/// La liste est paresseuse : 2056 lignes ne se rendent pas d'un bloc.
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
                    Text(group.isOrphan ? orphanLabel : (group.title ?? untitledLabel))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    // Ce qui distingue deux sections homonymes.
                    Text(group.firstKey)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                badges(group)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    /// Le même vocabulaire que les en-têtes, et le **même** code : `DiffStateStyle`
    /// est l'unique exemplaire du couple glyphe/teinte.
    @ViewBuilder
    private func badges(_ group: TranslationCoverage.DiffGroup) -> some View {
        HStack(spacing: 6) {
            ForEach([TranslationCoverage.DiffRow.State.empty, .missing], id: \.self) { state in
                let count = group.remaining(state)
                if count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: DiffStateStyle.glyph(state)).font(.system(size: 9))
                        Text("\(count)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                    .foregroundColor(DiffStateStyle.tint(state))
                }
            }
        }
    }

    private var matches: [TranslationCoverage.DiffGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return groups }
        return groups.filter {
            ($0.title ?? "").lowercased().contains(needle)
                || $0.firstKey.lowercased().contains(needle)
        }
    }
}
