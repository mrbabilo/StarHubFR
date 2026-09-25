import SwiftUI

/// Panorama des mods de performance qui font en partie le même travail
/// (A5-T7, marche 1), dans la feuille « Conflits entre mods » des Alertes
/// système, sous `ModConflictSection`.
///
/// **Hors pastille, par construction** : cette vue lit le catalogue elle-même
/// et ne passe ni par `vm.healthIssues` ni par `ModConflictVerdicts`. Un
/// recouvrement n'est pas un conflit, il ne doit pas compter comme une alerte.
/// Les paires écartées vivent dans leur propre clé `UserDefaults`, pour ne pas
/// gonfler le compteur « N écarté(s) » des conflits juste au-dessus.
struct PerformanceOverlapSection: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    @AppStorage(UDKey.dismissedPerformanceOverlaps) private var dismissedRaw = ""

    var body: some View {
        let matches = PerformanceOverlapResolver.matches(in: vm.scanStore.mods.flattenedMods)
            .filter(\.bothEnabled)
        let dismissed = PerformanceOverlapDismissals.decode(dismissedRaw)
        let shown = matches.filter { !dismissed.contains($0.overlap.key) }
        let hidden = matches.count - shown.count

        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            HStack {
                Image(systemName: "speedometer")
                Text(localization.L(L10n.PerformanceOverlaps.title))
                    .font(AppDesign.Font.rowTitle(.bold))
                    .lineLimit(1)
            }
            Text(localization.L(L10n.PerformanceOverlaps.intro))
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if shown.isEmpty {
                Label(localization.L(L10n.PerformanceOverlaps.none), systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            }
            ForEach(shown, id: \.overlap.key) { match in
                row(match)
            }
            if hidden > 0 {
                HStack(spacing: AppDesign.Spacing.sm) {
                    Text(String(format: localization.L(L10n.Conflicts.dismissedCount), hidden))
                    Button(localization.L(L10n.PerformanceOverlaps.restore)) { dismissedRaw = "" }
                        .buttonStyle(.borderless)
                        .pointingHandCursor()
                }
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
            }
        }
        .padding(AppDesign.Spacing.lg)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
    }

    private func row(_ match: PerformanceOverlapMatch) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
            HStack(spacing: AppDesign.Spacing.xs) {
                Text("\(match.firstMod.name) × \(match.secondMod.name)")
                    .font(AppDesign.Font.body(.medium))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: AppDesign.Spacing.sm)
                Button(localization.L(L10n.Conflicts.dismissButton)) {
                    dismissedRaw = PerformanceOverlapDismissals.dismissing(match.overlap.key, in: dismissedRaw)
                }
                .buttonStyle(.borderless)
                .font(AppDesign.Font.footnote)
                .foregroundColor(.secondary)
                .pointingHandCursor()
            }
            PerformanceOverlapDetails(match: match, localization: localization)
        }
    }
}

/// Le détail commun au panorama et à la fiche : les méthodes, l'option qui en
/// ajoute, et les versions décompilées.
struct PerformanceOverlapDetails: View {
    let match: PerformanceOverlapMatch
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        let overlap = match.overlap
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: localization.L(L10n.PerformanceOverlaps.methods),
                        overlap.sharedMethods.count, overlap.sharedMethods.joined(separator: ", ")))
                .lineLimit(3)
            if let option = overlap.conditionalOption {
                Text(String(format: localization.L(L10n.PerformanceOverlaps.conditional),
                            overlap.conditionalMethods.count, option))
                    .lineLimit(2)
            }
            Text(String(format: localization.L(L10n.PerformanceOverlaps.measured), measuredVersions))
                .lineLimit(2)
        }
        .font(AppDesign.Font.footnote)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// « UltraSmooth 2.3.7 · Radiance 2.2.1 », suivi d'un avertissement pour
    /// chaque mod dont la version installée n'est pas celle décompilée.
    private var measuredVersions: String {
        [match.firstMod, match.secondMod].compactMap { mod -> String? in
            guard let member = match.overlap.member(mod.uniqueId) else { return nil }
            let base = "\(mod.name) \(member.measuredVersion)"
            guard match.isRemeasureNeeded(for: mod) else { return base }
            return base + " " + String(format: localization.L(L10n.PerformanceOverlaps.installedDiffers), mod.version)
        }
        .joined(separator: " · ")
    }
}

/// Dans la fiche d'un mod (onglet État) : une ligne par partenaire **actif**
/// du catalogue. Montrée aussi quand le mod lui-même est en pause — c'est
/// avant de l'activer qu'on veut savoir qu'il refera le travail d'un autre.
struct PerformanceOverlapDetailRows: View {
    var vm: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let mod: ModItem
    @AppStorage(UDKey.dismissedPerformanceOverlaps) private var dismissedRaw = ""

    var body: some View {
        let dismissed = PerformanceOverlapDismissals.decode(dismissedRaw)
        let matches = PerformanceOverlapResolver.matches(in: vm.scanStore.mods.flattenedMods)
            .filter { match in
                guard let partner = match.partner(of: mod.folderName) else { return false }
                return partner.isEnabled && !dismissed.contains(match.overlap.key)
            }
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.sm) {
                Text(localization.L(L10n.PerformanceOverlaps.title))
                    .font(AppDesign.Font.body(.semibold))
                ForEach(matches, id: \.overlap.key) { match in
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                        HStack(spacing: AppDesign.Spacing.xs) {
                            Text(String(format: localization.L(L10n.PerformanceOverlaps.sameWorkAs),
                                        match.partner(of: mod.folderName)?.name ?? ""))
                                .font(AppDesign.Font.body(.medium))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(localization.L(L10n.Conflicts.dismissButton)) {
                                dismissedRaw = PerformanceOverlapDismissals.dismissing(match.overlap.key, in: dismissedRaw)
                            }
                            .buttonStyle(.borderless)
                            .font(AppDesign.Font.footnote)
                            .foregroundColor(.secondary)
                            .pointingHandCursor()
                        }
                        PerformanceOverlapDetails(match: match, localization: localization)
                    }
                }
                Text(localization.L(L10n.PerformanceOverlaps.notAConflict))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
