import Foundation
import Testing
@testable import StarHubTHCore

/// Ce qu'un lot de pré-traduction retient de chaque ligne, et quand il
/// s'arrête.
///
/// Cette comptabilité vivait dans `runBatch` (ViewModel), mêlée au réseau et
/// à l'écriture disque : six compteurs, une coupure de secours et une sortie
/// de boucle nommée, dont aucune règle n'était vérifiée.
struct TranslationBatchRunTests {

    private func entry(_ en: String, _ fr: String) -> GlossaryEntry {
        GlossaryEntry(en: en, fr: fr, kind: .item)
    }

    // MARK: - Ce qui est compté

    @Test func aWrittenTranslationCounts() {
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .translated("Bonjour", by: .local),
                       glossaryMatches: [], writeSucceeded: true, cancelled: false)
        #expect(run.report.translated == 1)
        #expect(run.report.translatedByFallback == 0)
        #expect(run.report.errors == 0)
    }

    @Test func aTranslationFromTheOnlineFallbackIsCountedApart() {
        // La provenance doit être visible, jamais devinée : c'est elle qui dit
        // à l'utilisateur ce qui est parti chez un tiers.
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .translated("Bonjour", by: .fallback),
                       glossaryMatches: [], writeSucceeded: true, cancelled: false)
        #expect(run.report.translated == 1)
        #expect(run.report.translatedByFallback == 1)
    }

    @Test func aTranslationThatFailedToBeWrittenIsAnError() {
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .translated("Bonjour", by: .local),
                       glossaryMatches: [], writeSucceeded: false, cancelled: false)
        #expect(run.report.translated == 0)
        #expect(run.report.errors == 1)
    }

    @Test func aRefusedRowIsNamedRatherThanCounted() {
        // L'écran propose de reprendre ces lignes à la main : un compteur ne
        // dirait pas lesquelles.
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "dialogue/greeting", outcome: .refusedTokens(missing: ["{{name}}"]),
                       glossaryMatches: [], writeSucceeded: false, cancelled: false)
        #expect(run.report.refusedRowIDs == ["dialogue/greeting"])
        #expect(run.report.errors == 0)
    }

    @Test func anEndpointErrorCounts() {
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .endpointError("500"),
                       glossaryMatches: [], writeSucceeded: false, cancelled: false)
        #expect(run.report.errors == 1)
    }

    @Test func anEndpointErrorCausedByOurOwnCancellationIsNotAnError() {
        // `data(for:)` honore l'annulation : la requête en vol échoue par
        // notre fait. La compter ferait rapporter une erreur fantôme à chaque
        // arrêt demandé par l'utilisateur.
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .endpointError("cancelled"),
                       glossaryMatches: [], writeSucceeded: false, cancelled: true)
        #expect(run.report.errors == 0)
    }

    // MARK: - Le glossaire ignoré

    @Test func aGlossaryTermTheEngineDidNotReuseIsCountedSoftly() {
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .translated("Il prend la faux", by: .local),
                       glossaryMatches: [entry("scythe", "faux"), entry("hoe", "houe")],
                       writeSucceeded: true, cancelled: false)
        #expect(run.report.softGlossaryIgnored == 1)
        #expect(run.report.translated == 1)   // jamais bloquant
    }

    @Test func anUnwrittenTranslationDoesNotFeedTheGlossarySignal() {
        // Le signalement porte sur ce qui est **sur le disque**. Compter une
        // proposition jamais écrite ferait accuser l'IA d'un texte que
        // personne ne lira.
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .translated("Il prend la lame", by: .local),
                       glossaryMatches: [entry("scythe", "faux")],
                       writeSucceeded: false, cancelled: false)
        #expect(run.report.softGlossaryIgnored == 0)
    }

    // MARK: - La coupure du secours

    @Test func anExhaustedQuotaStopsTheFallbackAndIsNamed() {
        var run = TranslationBatchRun(hasLocalEngine: true)
        let step = run.record(rowID: "a", outcome: .quotaExhausted,
                              glossaryMatches: [], writeSucceeded: false, cancelled: false)
        #expect(step.dropsFallback)
        #expect(run.report.fallbackStop == .quotaExhausted)
        #expect(run.report.errors == 1)
    }

    @Test func aRefusedRateAndARefusedKeyAreToldApart() {
        // Deux causes, deux remèdes : un quota se règle chez DeepL, un rythme
        // refusé s'attend, une clé refusée se change dans les réglages.
        var rate = TranslationBatchRun(hasLocalEngine: true)
        _ = rate.record(rowID: "a", outcome: .fallbackRateLimited,
                        glossaryMatches: [], writeSucceeded: false, cancelled: false)
        var key = TranslationBatchRun(hasLocalEngine: true)
        _ = key.record(rowID: "a", outcome: .fallbackUnauthorized,
                       glossaryMatches: [], writeSucceeded: false, cancelled: false)
        #expect(rate.report.fallbackStop == .rateLimited)
        #expect(key.report.fallbackStop == .unauthorized)
    }

    @Test func theLoopGoesOnWhenTheLocalEngineIsStillInTheRace() {
        var run = TranslationBatchRun(hasLocalEngine: true)
        let step = run.record(rowID: "a", outcome: .quotaExhausted,
                              glossaryMatches: [], writeSucceeded: false, cancelled: false)
        #expect(!step.stopsLoop)
    }

    @Test func theLoopStopsWhenNothingIsLeftToTranslateWith() {
        // Sans IA locale, continuer collectionnerait une erreur par clé
        // restante — le rapport a déjà dit ce qui s'est passé.
        var run = TranslationBatchRun(hasLocalEngine: false)
        let step = run.record(rowID: "a", outcome: .quotaExhausted,
                              glossaryMatches: [], writeSucceeded: false, cancelled: false)
        #expect(step.stopsLoop)
    }

    @Test func anOrdinaryLineNeverStopsTheLoop() {
        var run = TranslationBatchRun(hasLocalEngine: false)
        let step = run.record(rowID: "a", outcome: .translated("Bonjour", by: .local),
                              glossaryMatches: [], writeSucceeded: true, cancelled: false)
        #expect(!step.stopsLoop)
        #expect(!step.dropsFallback)
    }

    // MARK: - Le bilan

    @Test func theSummaryLineCarriesEveryCount() {
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .translated("Bonjour", by: .fallback),
                       glossaryMatches: [entry("scythe", "faux")],
                       writeSucceeded: true, cancelled: false)
        _ = run.record(rowID: "b", outcome: .refusedTokens(missing: ["{{n}}"]),
                       glossaryMatches: [], writeSucceeded: false, cancelled: false)
        _ = run.record(rowID: "c", outcome: .quotaExhausted,
                       glossaryMatches: [], writeSucceeded: false, cancelled: false)

        let line = run.summary(mod: "SVE")
        #expect(line.contains("SVE"))
        #expect(line.contains("1 traduites"))
        #expect(line.contains("dont 1 par le secours en ligne"))
        #expect(line.contains("1 refusées"))
        #expect(line.contains("1 erreurs"))
        #expect(line.contains("1 termes glossaire ignorés"))
        #expect(line.contains("secours coupé"))
    }

    @Test func aSummaryWithoutAStopSaysNothingAboutTheFallback() {
        var run = TranslationBatchRun(hasLocalEngine: true)
        _ = run.record(rowID: "a", outcome: .translated("Bonjour", by: .local),
                       glossaryMatches: [], writeSucceeded: true, cancelled: false)
        #expect(!run.summary(mod: "SVE").contains("secours coupé"))
    }
}
