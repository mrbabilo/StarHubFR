import SwiftUI

/// Sonde en tête (`ModsToLoadEarly`), réglage de la carte « Sonde » : sans
/// elle les chiffres du démarrage sont faux. **Toujours réversible** — pas
/// en tête (jamais demandé ou refusé) → le constat et l'offre ; consenti →
/// une ligne d'état colorée (icône + texte, jamais la couleur seule) avec son
/// geste. Le refus effaçait le bouton et rendait le choix définitif
/// (constat de l'auteur, 2026-10-03).
/// L'état vient du **fichier** relu (`ProbeLoadOrder.status`), pas de la
/// dernière action de l'app : un lancement par Steam ne passe pas par elle.
struct PerformanceLoadsProbeFirst: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    /// `nil` = jamais demandé ; la vérité reste dans `UserDefaults`.
    @Binding var consent: Bool?
    /// Réconcilié puis relu à l'apparition, après chaque geste et à chaque
    /// nouveau lancement — jamais dans `body`.
    @State private var listed: Bool?
    @State private var confirm = false

    var body: some View {
        content
            .onAppear(perform: refresh)
            .onChange(of: store.lastLaunch?.record.id) { refresh() }
            .confirmationDialog(localization.L(L10n.Performance.loadsProbeFirstAction), isPresented: $confirm) {
                Button(localization.L(L10n.Performance.loadsProbeFirstAction)) { setConsent(true) }
            } message: {
                Text(localization.L(L10n.Performance.loadsProbeFirstConfirm))
            }
    }

    private var probeActive: Bool { ProbeLoadOrder.isProbeActive(in: viewModel.mods) }

    private var status: ProbeLoadOrder.Status {
        ProbeLoadOrder.status(consent: consent, probeActive: probeActive, listed: listed,
                              lastLaunchFirst: store.lastLaunch?.probeLoadsFirst)
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .notAsked, .declined:
            // Jamais demandé : mis en avant ; refusé : discret, mais le geste reste.
            banner(icon: "arrow.up.to.line",
                   color: status == .notAsked ? AppDesign.Color.accent : AppDesign.Color.paused,
                   text: L10n.Performance.loadsProbeNotFirst) {
                Button(localization.L(L10n.Performance.loadsProbeFirstAction)) { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .clickableCursor()
            }
        case .active:
            banner(icon: "checkmark.circle.fill", color: AppDesign.Color.success,
                   text: L10n.Performance.loadsProbeFirstActive) { undo }
        case .pending:
            banner(icon: "clock.fill", color: AppDesign.Color.info,
                   text: L10n.Performance.loadsProbeFirstPending) { undo }
        case .notApplied:
            banner(icon: "exclamationmark.triangle.fill", color: AppDesign.Color.warning,
                   text: L10n.Performance.loadsProbeFirstFailed) {
                Button(localization.L(L10n.Performance.loadsProbeFirstRetry)) { sync(consent) }.clickableCursor()
                undo
            }
        case .probePaused:
            banner(icon: "pause.circle.fill", color: AppDesign.Color.paused,
                   text: L10n.Performance.loadsProbeFirstPaused) { undo }
        case .smapiMissing:
            banner(icon: "questionmark.folder.fill", color: AppDesign.Color.warning,
                   text: L10n.Performance.loadsProbeFirstNoSmapi) { undo }
        }
    }

    private var undo: some View {
        Button(localization.L(L10n.Performance.loadsProbeFirstUndo)) { setConsent(false) }.clickableCursor()
    }

    /// Texte au-dessus des gestes : tient à 560 pt, libellé FR le plus long compris.
    private func banner<Actions: View>(icon: String, color: Color, text: String,
                                       @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesign.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)   // le texte dit l'état
            VStack(alignment: .leading, spacing: AppDesign.Spacing.xs) {
                Text(localization.L(text))
                    .font(AppDesign.Font.body)
                    .fixedSize(horizontal: false, vertical: true)
                WrapHStack(spacing: AppDesign.Spacing.sm) { actions() }
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(AppDesign.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(AppDesign.Opacity.light),
                    in: RoundedRectangle(cornerRadius: AppDesign.Radius.section))
        .overlay(RoundedRectangle(cornerRadius: AppDesign.Radius.section)
            .stroke(color.opacity(AppDesign.Opacity.strong), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    // MARK: — Gestes

    private func setConsent(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: UDKey.probeLoadEarlyConsent)
        consent = value
        sync(value)
    }

    private func sync(_ value: Bool?) {
        listed = ProbeLoadOrder.reconcile(gameDir: viewModel.gameDir, consent: value, probeActive: probeActive)
    }

    private func refresh() { sync(consent) }
}
