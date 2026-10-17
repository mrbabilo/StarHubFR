import SwiftUI

/// X6 / E2 (audit UX 2026-10-16) — les créneaux de la bande de méta d'une
/// ligne de mod, sortis de `ModListRow.swift` (plafond de taille). En
/// colonnes fixes au large, à leur largeur naturelle sous le seuil
/// (`compactRow`) : à 821 pt, chaque valeur passait seule sur sa ligne.
extension ModListRow {
    /// En étroit, ce que la bande ne montre plus : les deux dates et les
    /// langues, à l'infobulle de la bande.
    func compactMetaHelp(updated: Date?, installed: Date?, langs: [String]) -> String? {
        var parts: [String] = []
        if let updated { parts.append(updated.formatted(.relative(presentation: .named))) }
        if let installed { parts.append(installed.formatted(date: .abbreviated, time: .omitted)) }
        if !langs.isEmpty { parts.append(langs.map { $0.uppercased() }.joined(separator: " ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Une valeur de la bande, précédée de son icône.
    func metaValue(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(AppDesign.Font.iconXXS)
            Text(text).lineLimit(1)
        }
    }

    /// La couverture française **ferme** la bande, juste après les codes de
    /// langue dont elle précise l'un des membres : les deux se lisent ensemble,
    /// et le bout de ligne en fait un point d'arrivée du regard plutôt qu'un
    /// préambule à franchir avant les dates.
    @ViewBuilder
    func frenchSlot(langs: [String]) -> some View {
        Group {
            if langs.contains("fr") {
                FrenchCoverageBadge(
                    percent: vm.frenchCoverage(for: mod),
                    // Un code de langue, pas une phrase : il ne se traduit pas,
                    // exactement comme la liste des langues à côté.
                    unmeasuredLabel: "FR",
                    percentFormat: localization.L(L10n.Mods.frCoveragePercent)
                )
            }
        }
        .frame(width: compactRow ? nil : ModListRow.Column.french, alignment: .leading)
    }

    @ViewBuilder
    func updatedSlot(_ updated: Date?) -> some View {
        Group {
            if let updated {
                metaValue("clock.arrow.circlepath",
                          updated.formatted(.relative(presentation: .named)))
            }
        }
        .frame(width: compactRow ? nil : ModListRow.Column.updated, alignment: .leading)
    }

    @ViewBuilder
    func installedSlot(_ installed: Date?) -> some View {
        Group {
            if let installed {
                metaValue("tray.and.arrow.down",
                          installed.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .frame(width: compactRow ? nil : ModListRow.Column.installed, alignment: .leading)
    }

    @ViewBuilder
    func weightSlot(_ size: Int64?) -> some View {
        Group {
            if let size { ModWeightLabel(bytes: size) }
        }
        .frame(width: compactRow ? nil : ModListRow.Column.weight, alignment: .leading)
    }

    /// Jusqu'à 76 caractères de codes sur le parc réel : borné à ce que la
    /// place permet, avec la liste entière à l'infobulle.
    @ViewBuilder
    func languagesLabel(_ langs: [String]) -> some View {
        let codes = langs.map { $0.uppercased() }.joined(separator: " ")
        Group {
            if !langs.isEmpty {
                metaValue("globe", codes)
                    .truncationMode(.tail)
                    .help(codes)
            }
        }
        .frame(width: compactRow ? nil : ModListRow.Column.languages, alignment: .leading)
    }
}

/// Ligne de mod étroite (E2) : mesurée une fois sur la pile des lignes
/// (`ModRowsStack`), lue par chaque ligne.
private struct ModRowCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var modRowCompact: Bool {
        get { self[ModRowCompactKey.self] }
        set { self[ModRowCompactKey.self] = newValue }
    }
}
