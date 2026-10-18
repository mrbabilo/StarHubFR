import SwiftUI

extension UpdatesView {
    /// En-tête commun des pages (audit UX 2026-10-02). Le compte vient de
    /// `UpdateCount.pending`, la fonction du badge de la barre latérale et de
    /// la tuile de l'accueil : trois endroits, un seul chiffre. Ce qu'un zéro
    /// permet d'affirmer vient de `UpdateCheckVerdict` ; la minute rafraîchit
    /// l'âge de la vérification, page ouverte.
    var pageHeader: some View {
        // P5-6b : le verdict sur le total, le sous-titre sépare actifs et pause.
        let counts = vm.pendingUpdateCounts
        let verdict = vm.updateCheckVerdict(pending: counts.total)
        return TimelineView(.periodic(from: .now, by: 60)) { context in
            PageContextBar(icon: "arrow.triangle.2.circlepath",
                           context: headerSubtitle(verdict, counts: counts, now: context.date),
                           // Le vert est réservé au zéro mesuré sans réserve.
                           tint: headerTint(verdict))
        }
        .padding(.horizontal, AppDesign.Spacing.xl)
        .padding(.vertical, AppDesign.Spacing.md)
    }

    private func headerSubtitle(_ verdict: UpdateCheckVerdict, counts: PendingUpdateCounts, now: Date) -> String {
        let locale = Locale(identifier: localization.currentLanguage)
        switch verdict {
        case .pending(_, let checkedAt?):
            return String(format: localization.L(L10n.Updates.headerPendingChecked),  // E8
                          pendingText(counts),
                          UpdateCheckVerdict.ageText(since: checkedAt, now: now, locale: locale))
        case .pending(_, nil):
            return pendingText(counts)
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

    /// « 1 mise à jour en attente · 5 en pause » ; sans mise à jour en pause,
    /// la première moitié seule (P5-6b).
    private func pendingText(_ counts: PendingUpdateCounts) -> String {
        let active = localization.plural(L10n.Updates.headerPending, counts.active)
        guard counts.paused > 0 else { return active }
        return String(format: localization.L(L10n.Updates.headerWithPaused), active, Int64(counts.paused))
    }
}
