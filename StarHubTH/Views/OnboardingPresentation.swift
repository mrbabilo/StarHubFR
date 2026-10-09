import SwiftUI

/// Déclencheurs + sheet du guide de premier lancement, extraits du `body`
/// de `MainView` : l'ajout de six modificateurs à sa chaîne existante faisait
/// dépasser au compilateur son budget de vérification de types (« unable to
/// type-check this expression in reasonable time »), piège déjà rencontré sur
/// `AttentionCounterTile`.
///
/// Le garde reproduit les conditions de `MainView.canPresentReleaseAlert` en
/// plus de la valeur passée : fenêtre révélée (`isLaunching` faux), pas
/// d'alerte de release (`availableAppRelease` nil), créneau libre (valeur
/// `canPresentReleaseAlert` fraîchement recalculée par `MainView`).
struct OnboardingPresentation: ViewModifier {
    @Binding var showOnboarding: Bool
    @AppStorage(UDKey.onboardingCompleted) private var onboardingCompleted = false
    var isLaunching: Bool
    var availableAppRelease: GitHubRelease?
    var canPresentReleaseAlert: Bool
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore

    private var mayPresent: Bool {
        !onboardingCompleted && !isLaunching && canPresentReleaseAlert
            && availableAppRelease == nil
    }

    private func presentIfNeeded() {
        guard mayPresent else { return }
        showOnboarding = true
    }

    func body(content: Content) -> some View {
        content
            // `onAppear` couvre le lancement déjà fini ; `isLaunching` le
            // lancement normal (après le `finish()` du splash) ; feuilles et
            // release rattrapent quand le créneau se libère ; la clé rejoue
            // depuis les Réglages.
            .onAppear { presentIfNeeded() }
            .onChange(of: onboardingCompleted) { _, completed in
                if !completed { presentIfNeeded() }
            }
            .onChange(of: isLaunching) { _, launching in
                if !launching { presentIfNeeded() }
            }
            .onChange(of: availableAppRelease) { _, release in
                if release == nil { presentIfNeeded() }
            }
            .onChange(of: canPresentReleaseAlert) { _, free in
                if free { presentIfNeeded() }
            }
            .sheet(isPresented: $showOnboarding, onDismiss: {
                // Tout moyen de fermer (Terminer, Passer le guide, Esc)
                // marque le guide comme vu — il ne revient que si les
                // Réglages le redemandent.
                UserDefaults.standard.set(true, forKey: UDKey.onboardingCompleted)
            }) {
                OnboardingView(viewModel: viewModel, localization: localization) {
                    showOnboarding = false
                }
            }
    }
}
