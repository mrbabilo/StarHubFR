import Foundation
import Testing
@testable import StarHubTHCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

@Suite struct DownloadRateEstimatorTests {

    /// Un seul relevé ne mesure rien : il n'y a pas d'intervalle.
    @Test func oneSampleGivesNoRate() {
        var estimator = DownloadRateEstimator()
        estimator.record(totalBytes: 1_000, at: t0)
        #expect(estimator.bytesPerSecond == nil)
    }

    /// Deux relevés trop rapprochés non plus : un débit calculé sur 30 ms est
    /// un artefact, et l'estimation de temps qui en découlerait danserait.
    @Test func samplesTooCloseTogetherGiveNoRate() {
        var estimator = DownloadRateEstimator()
        estimator.record(totalBytes: 0, at: t0)
        estimator.record(totalBytes: 30_000, at: t0.addingTimeInterval(0.03))
        #expect(estimator.bytesPerSecond == nil)
    }

    @Test func theRateIsBytesOverElapsedTime() {
        var estimator = DownloadRateEstimator()
        estimator.record(totalBytes: 0, at: t0)
        estimator.record(totalBytes: 2_000_000, at: t0.addingTimeInterval(2))
        #expect(estimator.bytesPerSecond == 1_000_000)
    }

    /// Le lissage porte sur une fenêtre courte, pas sur tout le
    /// téléchargement : une connexion qui s'effondre doit se voir tout de
    /// suite, c'est le moment où l'utilisateur regarde.
    @Test func oldSamplesLeaveTheWindow() {
        var estimator = DownloadRateEstimator(window: 3)
        // Dix secondes à 1 Mo/s…
        for second in 0...10 {
            estimator.record(totalBytes: Int64(second) * 1_000_000,
                             at: t0.addingTimeInterval(Double(second)))
        }
        // …puis trois secondes à 100 ko/s.
        for second in 11...13 {
            estimator.record(totalBytes: 10_000_000 + Int64(second - 10) * 100_000,
                             at: t0.addingTimeInterval(Double(second)))
        }
        let rate = try! #require(estimator.bytesPerSecond)
        // Une moyenne depuis le début aurait annoncé ~790 ko/s.
        #expect(rate < 200_000)
    }

    /// La fenêtre reste large même quand les relevés sont nombreux : purger
    /// jusqu'au premier relevé *à l'intérieur* de la fenêtre la raccourcirait
    /// à chaque appel, et le débit redeviendrait quasi instantané.
    @Test func theWindowKeepsItsSpanUnderHeavySampling() {
        var estimator = DownloadRateEstimator(window: 3)
        for step in 0...300 {
            estimator.record(totalBytes: Int64(step) * 10_000,
                             at: t0.addingTimeInterval(Double(step) * 0.01))
        }
        // 300 relevés sur 3 s à 1 Mo/s.
        let rate = try! #require(estimator.bytesPerSecond)
        #expect(abs(rate - 1_000_000) < 50_000)
    }

    /// Un total qui recule n'a pas de sens : mieux vaut ne rien dire qu'un
    /// débit négatif.
    @Test func aShrinkingTotalGivesNoRate() {
        var estimator = DownloadRateEstimator()
        estimator.record(totalBytes: 5_000, at: t0)
        estimator.record(totalBytes: 1_000, at: t0.addingTimeInterval(1))
        #expect(estimator.bytesPerSecond == nil)
    }

    @Test func resetForgetsEverything() {
        var estimator = DownloadRateEstimator()
        estimator.record(totalBytes: 0, at: t0)
        estimator.record(totalBytes: 1_000_000, at: t0.addingTimeInterval(1))
        #expect(estimator.bytesPerSecond != nil)
        estimator.reset()
        #expect(estimator.bytesPerSecond == nil)
    }
}

@Suite struct DownloadProgressTests {

    private func progress(_ received: Int64, of total: Int64?,
                          rate: Double? = nil) -> DownloadProgress {
        DownloadProgress(bytesReceived: received, totalBytes: total, bytesPerSecond: rate)
    }

    // MARK: - Avec une taille annoncée

    @Test func theFractionIsReceivedOverTotal() {
        #expect(progress(50, of: 200).fractionCompleted == 0.25)
        #expect(progress(50, of: 200).displayPercent == 25)
    }

    /// Un serveur qui annonce une taille et en envoie davantage existe : une
    /// barre remplie à 110 % déborderait de son cadre.
    @Test func moreBytesThanAnnouncedStaysAtOne() {
        #expect(progress(300, of: 200).fractionCompleted == 1)
        #expect(progress(300, of: 200).displayPercent == 100)
    }

    /// « 100 » n'est rendu qu'une fois tout reçu : un téléchargement annoncé
    /// fini qui continue est le pire des affichages.
    @Test func almostFinishedNeverReadsAsHundred() {
        #expect(progress(9_999, of: 10_000).displayPercent == 99)
    }

    @Test func theRemainingTimeIsWhatIsLeftOverTheRate() {
        let p = progress(2_000_000, of: 10_000_000, rate: 2_000_000)
        #expect(p.estimatedTimeRemaining == 4)
    }

    @Test func nothingLeftToDownloadMeansNoWait() {
        #expect(progress(10_000, of: 10_000, rate: 1_000).estimatedTimeRemaining == 0)
    }

    // MARK: - Sans taille annoncée — le cas que le CDN impose

    /// `expectedContentLength` vaut `-1` quand le serveur ne l'annonce pas :
    /// le laisser passer donnerait une division par zéro déguisée en
    /// pourcentage.
    @Test func anUnknownTotalIsNotASize() {
        let p = DownloadProgress(bytesReceived: 1_000, totalBytes: -1, bytesPerSecond: 500)
        #expect(p.totalBytes == nil)
        #expect(p.fractionCompleted == nil)
        #expect(p.displayPercent == nil)
        #expect(p.estimatedTimeRemaining == nil)
    }

    @Test func aZeroTotalIsNotASizeEither() {
        #expect(progress(1_000, of: 0).totalBytes == nil)
        #expect(progress(1_000, of: 0).fractionCompleted == nil)
    }

    /// …mais le volume reçu et le débit, eux, sont vrais : c'est ce qu'il reste
    /// à montrer.
    @Test func volumeAndRateSurviveAnUnknownTotal() {
        let p = DownloadProgress(bytesReceived: 4_096, totalBytes: nil, bytesPerSecond: 1_024)
        #expect(p.bytesReceived == 4_096)
        #expect(p.bytesPerSecond == 1_024)
    }

    /// Sans débit mesurable, pas de temps restant : jamais « ∞ », jamais zéro
    /// par défaut.
    @Test func noRateMeansNoEstimate() {
        #expect(progress(1_000, of: 10_000, rate: nil).estimatedTimeRemaining == nil)
        #expect(progress(1_000, of: 10_000, rate: 0).estimatedTimeRemaining == nil)
    }
}

/// Le cas limite du repli : un téléchargement si lent que les notifications se
/// raréfient. Sans lui, le débit disparaîtrait au moment précis où il ralentit.
@Suite struct SlowDownloadRateTests {

    @Test func aSingleSampleInTheWindowStillMeasures() {
        var estimator = DownloadRateEstimator(window: 3)
        estimator.record(totalBytes: 0, at: t0)
        // Dix secondes plus tard : le relevé précédent est hors fenêtre, mais
        // c'est le seul point de comparaison qui existe.
        estimator.record(totalBytes: 10_000, at: t0.addingTimeInterval(10))
        let rate = try! #require(estimator.bytesPerSecond)
        #expect(rate == 1_000)
    }
}
