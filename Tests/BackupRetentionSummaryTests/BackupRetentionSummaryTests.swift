import Testing
@testable import StarHubTHCore

/// R1 — la phrase de rétention se lit dans les constantes du ménage
/// automatique : changer la règle change la phrase, sur les deux écrans.
@Suite("BackupRetentionSummary")
struct BackupRetentionSummaryTests {
    @Test func phraseCarriesThePolicyConstants() {
        #expect(BackupRetentionSummary.days == 30)
        #expect(BackupRetentionSummary.minimumKept == 5)
        let text = BackupRetentionSummary.automatic(localized: { _ in "%1$lld|%2$lld" })
        #expect(text == "30|5")
    }
}
