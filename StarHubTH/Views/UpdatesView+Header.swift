import SwiftUI

extension UpdatesView {
    /// En-tête commun des pages (audit UX 2026-10-02). Le compte vient de
    /// `UpdateCount.pending`, la fonction du badge de la barre latérale et de
    /// la tuile de l'accueil : trois endroits, un seul chiffre. Ce qu'un zéro
    /// permet d'affirmer vient de `UpdateCheckVerdict` ; la minute rafraîchit
    /// l'âge de la vérification, page ouverte.
    var pageHeader: some View {
        let pending = UpdateCount.pending(outOfDate: vm.outOfDateMods,
                                          nexusCount: vm.nexusUpdates.count) {
            vm.resolveModFolder(forLoggedName: $0)?.version
        }
        let verdict = vm.updateCheckVerdict(pending: pending)
        return TimelineView(.periodic(from: .now, by: 60)) { context in
            PageHeader(icon: "arrow.triangle.2.circlepath",
                       title: localization.L(L10n.Main.modUpdates),
                       subtitle: headerSubtitle(verdict, now: context.date),
                       // Le vert est réservé au zéro mesuré sans réserve.
                       tint: headerTint(verdict))
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.md)
    }

    private func headerSubtitle(_ verdict: UpdateCheckVerdict, now: Date) -> String {
        let locale = Locale(identifier: localization.currentLanguage)
        switch verdict {
        case .pending(let count, let checkedAt?):
            return String(format: localization.L(L10n.Updates.headerPendingChecked), Int64(count),
                          UpdateCheckVerdict.ageText(since: checkedAt, now: now, locale: locale))
        case .pending(let count, nil):
            return String(format: localization.L(L10n.Updates.headerPending), Int64(count))
        case .upToDate(let checkedAt):
            return String(format: localization.L(L10n.Updates.headerUpToDateChecked),
                          UpdateCheckVerdict.ageText(since: checkedAt, now: now, locale: locale))
        case .verifiableUpToDate(let checkedAt):
            return String(format: localization.L(L10n.Updates.headerVerifiableChecked),
                          UpdateCheckVerdict.ageText(since: checkedAt, now: now, locale: locale))
        case .neverChecked:
            return localization.L(L10n.Updates.headerNeverChecked)
        }
    }

    /// Section Nexus vide. C'était `logs_system_alerts_section` — « Aucune
    /// alerte système » — sur la page des **mises à jour**, puis une coche
    /// verte « tous à jour » même sans aucune vérification aboutie. Le même
    /// verdict que l'en-tête : coche verte pour le zéro mesuré sans réserve,
    /// « vérifiables » quand des mods restent sans verdict (le bloc sous la
    /// liste les nomme) ou qu'on ne le sait pas.
    var nexusEmptyState: some View {
        let verdict = vm.updateCheckVerdict(pending: vm.nexusUpdates.count)
        let (glyph, color, key): (String, Color, String) = switch verdict {
        case .upToDate, .pending:
            ("checkmark.circle.fill", AppDesign.Color.success, L10n.Updates.allUpToDate)
        case .verifiableUpToDate:
            (AppDesign.Status.ok.symbol, .secondary, L10n.Updates.allVerifiedUpToDate)
        case .neverChecked:
            ("questionmark.circle", .secondary, L10n.Updates.neverChecked)
        }
        return HStack(spacing: 6) {
            Image(systemName: glyph).foregroundColor(color)
            Text(localization.L(key))
        }
        .font(AppDesign.Font.caption)
        .foregroundColor(.secondary)
    }

    private func headerTint(_ verdict: UpdateCheckVerdict) -> Color {
        switch verdict {
        case .pending: return AppDesign.Color.info
        case .upToDate: return AppDesign.Color.success
        case .verifiableUpToDate, .neverChecked: return AppDesign.Color.accent
        }
    }
}
