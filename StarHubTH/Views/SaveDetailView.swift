import SwiftUI

/// R6 (audit UX 2026-10-16, décision de l'auteur) — la page d'une partie, à
/// trois segments : Détails (l'éditeur), Mods (ce que la partie doit aux mods,
/// en lecture), Historique (ses sauvegardes de secours). Avant, l'éditeur et
/// l'historique étaient deux pages pleines qui se renvoyaient l'une à
/// l'autre, et les mods se cherchaient au milieu du formulaire, où Entrée
/// enregistre.
///
/// Les trois segments restent montés (patron de `DiagnosticsView`) : passer à
/// l'historique et revenir ne perd pas une saisie en cours de l'éditeur.
struct SaveDetailView: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    let save: SaveGameInfo
    @Binding var currentTab: SidebarDestination
    /// Une seule alerte pour la page (patron de `SaveEditorConfirmation`) : l'écriture sur une
    /// partie modifiée sur disque, ou la fermeture avec des modifications non enregistrées.
    @State private var confirmation: Confirmation?
    @State private var pendingSaveAction: (() -> Void)?

    private enum Confirmation { case staleEdit, discardChanges }

    var body: some View {
        let navigation = viewModel.navigationStore
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SaveSegment.allCases, id: \.self) { segment in
                    segmentButton(segment, navigation: navigation)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(AppDesign.Opacity.subtle)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(AppDesign.Opacity.light), lineWidth: 0.5))
            .fixedSize()
            .padding(.vertical, AppDesign.Spacing.sm)
            .zIndex(2)
            Divider()
            ZStack {
                if let session = navigation.editSession {
                    shown(.details, navigation.saveSegment) {
                        SaveEditorView(vm: viewModel, localization: localization, session: session,
                                       currentTab: $currentTab,
                                       onClose: { close(session) })
                    }
                    shown(.chests, navigation.saveSegment) {
                        SaveChestsView(session: session, localization: localization)
                    }
                }
                shown(.mods, navigation.saveSegment) { modsSegment }
                shown(.history, navigation.saveSegment) {
                    SaveTimelineView(vm: viewModel, localization: localization, save: save)
                }
            }
            if let session = navigation.editSession { footer(session) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .alert(confirmationTitle,
               isPresented: Binding(get: { confirmation != nil },
                                    set: { if !$0 { confirmation = nil; pendingSaveAction = nil } }),
               presenting: confirmation) { pending in
            switch pending {
            case .staleEdit:
                Button(localization.L(L10n.Saves.overwriteAnyway), role: .destructive) {
                    pendingSaveAction?()
                    pendingSaveAction = nil
                }
            case .discardChanges:
                Button(localization.L(L10n.Saves.discardChanges), role: .destructive) {
                    viewModel.navigationStore.setEditingSave(nil)
                }
            }
            Button(localization.L(L10n.Saves.cancel), role: .cancel) { pendingSaveAction = nil }
        } message: { pending in
            switch pending {
            case .staleEdit: Text(localization.L(L10n.Saves.confirmStaleEditMsg))
            case .discardChanges: Text(localization.L(L10n.Saves.discardChangesMsg))
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .staleEdit: return localization.L(L10n.Saves.confirmStaleEdit)
        case .discardChanges: return localization.L(L10n.Saves.discardChangesTitle)
        case nil: return ""
        }
    }

    /// Le pied commun aux segments : le seul « Enregistrer les modifications (n) » de la page, et
    /// son seul ⌘S. Il reste hors de `shown`, donc jamais désactivé avec un segment caché.
    private func footer(_ session: SaveEditSession) -> some View {
        let count = session.changeCount
        return VStack(spacing: 0) {
            Divider()
            HStack {
                Text(localization.L(L10n.Saves.backupNote))
                    .font(AppDesign.Font.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Button(count == 0 ? localization.L(L10n.Saves.saveChanges)
                       : String(format: localization.L(L10n.Saves.saveChangesCount), count)) {
                    confirmedOrWarn { performSave(session, overwriteNewer: $0) }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent).focusRing()
                .disabled(count == 0)  // un second clic pendant l'écriture : refusé par `beginOperation`
            }
            .padding(AppDesign.Spacing.lg)
        }
    }

    /// Fermer la page ; des modifications non enregistrées demandent confirmation.
    private func close(_ session: SaveEditSession) {
        if session.changeCount > 0 { confirmation = .discardChanges }
        else { viewModel.navigationStore.setEditingSave(nil) }
    }

    /// Every write path of the page goes through here. Save changed on disk since opening:
    /// deferred until the user confirms the overwrite (`action` gets `true`). Game running: no
    /// confirmation, the write itself refuses and says so (B5-T1).
    private func confirmedOrWarn(_ action: @escaping (_ overwriteNewer: Bool) -> Void) {
        if viewModel.isSaveStale(save) {
            pendingSaveAction = { action(true) }
            confirmation = .staleEdit
        } else {
            action(false)
        }
    }

    /// Une écriture pour la fiche et le sac, seulement s'ils ont changé ; la note de l'app à part.
    private func performSave(_ session: SaveEditSession, overwriteNewer: Bool) {
        viewModel.setNote(for: save.folderName, tag: session.noteTag, note: session.noteText)
        let edits = session.pendingEdits()
        guard edits.sheet != nil || edits.items != nil else { return viewModel.navigationStore.setEditingSave(nil) }
        viewModel.saveEdits(info: save, sheet: edits.sheet, items: edits.items,
                            expected: session.expectedStamp(overwriteNewer: overwriteNewer))
    }

    /// Les mods en pause qui ont laissé du contenu dans la partie, et les mods
    /// disparus qu'elle cite encore, avec « Nettoyer… ».
    private var modsSegment: some View {
        VStack(spacing: 0) {
            PageHeader(icon: "shippingbox", title: save.playerName, subtitle: save.farmName)
                .padding(.horizontal, AppDesign.Spacing.xl)
                .padding(.vertical, AppDesign.Spacing.md)
            Divider()
            Form {
                SavePausedFootprintSection(vm: viewModel, localization: localization, save: save, currentTab: $currentTab)
                SaveAbsentModsSection(vm: viewModel, localization: localization, save: save)
            }
            .formStyle(.grouped)
        }
    }

    private func shown(_ segment: SaveSegment, _ current: SaveSegment,
                       @ViewBuilder content: () -> some View) -> some View {
        let visible = segment == current
        return content()
            // Les trois segments restent montés. Le segment actif doit donc
            // passer au-dessus des contrôles macOS des segments cachés ;
            // sinon l'éditeur peut continuer à occuper la couche interactive.
            .zIndex(visible ? 1 : 0)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            // Un segment caché ne doit pas garder ses raccourcis : Entrée
            // enregistre dans l'éditeur, même invisible.
            .disabled(!visible)
            .accessibilityHidden(!visible)
    }

    private func label(_ segment: SaveSegment) -> String {
        switch segment {
        case .details: return localization.L(L10n.Saves.segmentDetails)
        case .chests:  return localization.L(L10n.Saves.segmentChests)
        case .mods:    return localization.L(L10n.Saves.segmentMods)
        case .history: return localization.L(L10n.Saves.timeline)
        }
    }

    private func segmentButton(_ segment: SaveSegment,
                               navigation: NavigationStore) -> some View {
        let title = label(segment)
        let selected = navigation.saveSegment == segment
        return Button { navigation.saveSegment = segment } label: {
            Text(title)
                .font(AppDesign.Font.caption(selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, AppDesign.Spacing.md)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color.accentColor.opacity(0.22) : .clear))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusRing(cornerRadius: 5)
        .foregroundColor(selected ? .primary : .secondary)
        .help(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
