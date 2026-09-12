import Testing
import Foundation
@testable import StarHubTHCore

/// Ce que l'app sait du compte Nexus : la clé, le compte, le quota — et ce
/// qui part avec quoi.
///
/// Les règles de décodage et de péremption sont prouvées ailleurs
/// (`NexusAccountTests`, `NexusQuotaTests`) ; ici, c'est que le store tienne
/// les trois couplages qui vivaient en affectations voisines.
@Suite struct NexusAccountStoreTests {

    private func account(premium: Bool, checkedAt: Date = Date()) -> NexusAccount {
        NexusAccount(name: "moi", isPremium: premium, checkedAt: checkedAt)
    }

    private func quota(_ hourlyRemaining: Int) -> NexusQuota {
        NexusQuota(hourly: .init(limit: 100, remaining: hourlyRemaining, reset: nil),
                   daily: nil, measuredAt: Date(timeIntervalSince1970: 1))
    }

    // MARK: - Le compte appartient à la clé

    /// Une clé neuve peut désigner un **autre** compte, d'un autre type :
    /// garder l'ancien afficherait « premium » à qui ne l'est plus.
    @Test func acceptingAKeyDropsTheAccountItKnew() {
        let s = NexusAccountStore()
        s.apply(hasApiKey: true, quota: nil, account: account(premium: true))
        s.keyAccepted()
        #expect(s.hasApiKey)
        #expect(s.account == nil)
    }

    /// Retirer la clé emporte compte **et** quota.
    @Test func clearingTheKeyTakesAccountAndQuotaWithIt() {
        let s = NexusAccountStore()
        s.apply(hasApiKey: true,
                quota: quota(90),
                account: account(premium: true))
        s.clearKey()
        #expect(s.hasApiKey == false)
        #expect(s.account == nil)
        #expect(s.quota == nil)
    }

    // MARK: - L'ignorance ne retire rien

    /// Le bouton de téléchargement direct ne disparaît que quand on **sait**
    /// que le compte n'y a pas droit. Ne pas savoir n'est pas un refus :
    /// mieux vaut un bouton qui échoue qu'un bouton absent chez quelqu'un qui
    /// y avait droit.
    @Test func anUnknownAccountDoesNotWithholdTheDirectDownload() {
        let s = NexusAccountStore()
        #expect(s.directDownloadUnavailable == false)      // on ignore
        s.setAccount(account(premium: true))
        #expect(s.directDownloadUnavailable == false)      // on sait : premium
        s.setAccount(account(premium: false))
        #expect(s.directDownloadUnavailable)               // on sait : non
    }

    // MARK: - Le renseignement vieillit

    @Test func anAbsentAccountAsksToBeFetched() {
        let s = NexusAccountStore()
        #expect(s.needsAccountRefresh())
    }

    /// Une semaine : assez court pour ne pas mentir longtemps, assez long
    /// pour ne pas interroger Nexus à chaque lancement.
    @Test func aWeekOldAccountAsksToBeRefreshedButAFreshOneDoesNot() {
        let s = NexusAccountStore()
        let now = Date(timeIntervalSince1970: 10_000_000)
        s.setAccount(account(premium: true, checkedAt: now))
        #expect(s.needsAccountRefresh(now: now.addingTimeInterval(6 * 24 * 3600)) == false)
        #expect(s.needsAccountRefresh(now: now.addingTimeInterval(8 * 24 * 3600)))
    }

    // MARK: - Le lot du lancement

    @Test func theLaunchBatchPublishesAllThree() {
        let s = NexusAccountStore()
        let q = quota(5)
        s.apply(hasApiKey: true, quota: q, account: account(premium: false))
        #expect(s.hasApiKey)
        #expect(s.quota == q)
        #expect(s.account?.isPremium == false)
    }

    @Test func theQuotaIsPublishedOnItsOwn() {
        let s = NexusAccountStore()
        let q = quota(42)
        s.setQuota(q)
        #expect(s.quota == q)
    }
}
