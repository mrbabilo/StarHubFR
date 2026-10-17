import Testing
@testable import StarHubTHCore

/// N-11 — un refus mène aux Réglages seulement quand sa cause s'y règle.
struct TranslationAssistFailureTests {

    @Test func aMissingOrRefusedKeyLeadsToTranslationSettings() {
        #expect(TranslationAssistFailure.noFallback.settings == .translationAI)
        #expect(TranslationAssistFailure.noEngine.settings == .translationAI)
        #expect(TranslationAssistFailure.stopped(.unauthorized).settings == .translationAI)
    }

    /// Le quota et le rythme se règlent chez DeepL ou en attendant.
    @Test func quotaAndRateLimitHaveNoSettingsRemedy() {
        #expect(TranslationAssistFailure.stopped(.quotaExhausted).settings == nil)
        #expect(TranslationAssistFailure.stopped(.rateLimited).settings == nil)
    }

    @Test func eachFailureKeepsItsOwnMessage() {
        let all: [TranslationAssistFailure] = [.noFallback, .noEngine, .stopped(.quotaExhausted),
                                               .stopped(.rateLimited), .stopped(.unauthorized)]
        #expect(Set(all.map(\.messageKey)).count == all.count)
    }
}
