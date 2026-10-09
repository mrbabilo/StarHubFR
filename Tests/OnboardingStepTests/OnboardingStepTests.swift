import Testing
@testable import StarHubTHCore

@Suite("Étapes du guide de premier lancement")
struct OnboardingStepTests {

    @Test func ordreCanoniqueHuitÉtapes() {
        #expect(OnboardingStep.allCases == [.welcome, .gameDir, .modsFolder,
                                            .smapi, .apiKey, .localAI,
                                            .extensions, .done])
    }

    @Test func clésDeTitreUniquesEtPréfixées() {
        let keys = OnboardingStep.allCases.map(\.titleKey)
        #expect(Set(keys).count == 8)
        #expect(keys.allSatisfy { $0.hasPrefix("onboarding_step_") })
    }

    @Test func titreParÉtape() {
        #expect(OnboardingStep.welcome.titleKey == "onboarding_step_welcome")
        #expect(OnboardingStep.gameDir.titleKey == "onboarding_step_game_dir")
        #expect(OnboardingStep.modsFolder.titleKey == "onboarding_step_mods")
        #expect(OnboardingStep.smapi.titleKey == "onboarding_step_smapi")
        #expect(OnboardingStep.apiKey.titleKey == "onboarding_step_api_key")
        #expect(OnboardingStep.localAI.titleKey == "onboarding_step_ai")
        #expect(OnboardingStep.extensions.titleKey == "onboarding_step_extensions")
        #expect(OnboardingStep.done.titleKey == "onboarding_step_done")
    }

    @Test func suivantSarrêteÀLaFin() {
        #expect(OnboardingStep.welcome.next == .gameDir)
        #expect(OnboardingStep.apiKey.next == .localAI)
        #expect(OnboardingStep.done.next == nil)
    }
}
