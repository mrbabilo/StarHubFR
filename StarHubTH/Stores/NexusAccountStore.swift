import Foundation
import Observation

/// Ce que l'app sait du **compte Nexus** : la clé est-elle posée, à qui
/// appartient-elle, et ce qu'il en reste au quota (cadrage §4, domaine 7,
/// tranche 2).
///
/// Le Trousseau n'entre pas ici. `NexusUpdateChecker.shared` garde la clé ;
/// le store n'en retient que le **fait** qu'elle a été acceptée — la nuance
/// compte : déclarer la clé configurée sans que le Trousseau l'ait prise
/// faisait afficher « configurée » à une UI dont la vérification suivante
/// repartait en `.noApiKey`.
///
/// Ce qu'il épine :
///
/// 1. **Le compte appartient à la clé.** Poser une clé neuve invalide le
///    compte connu : ce peut être un autre compte, d'un autre type.
/// 2. **Retirer la clé emporte compte et quota**, et eux seuls — les mises à
///    jour ne doivent rien à la clé, qui ne sert qu'au téléchargement
///    intégré et aux fiches.
/// 3. **L'ignorance ne retire rien.** Le téléchargement direct n'est déclaré
///    indisponible que quand on **sait** que le compte n'est pas premium :
///    mieux vaut un bouton qui échoue qu'un bouton absent chez quelqu'un qui
///    y avait droit.
@Observable
final class NexusAccountStore {

    /// Vrai quand une clé d'API est posée **et acceptée par le Trousseau**.
    private(set) var hasApiKey = false

    /// Le compte, `nil` tant qu'on ne sait pas.
    private(set) var account: NexusAccount?

    /// Dernier quota relevé, `nil` tant qu'aucune réponse de l'API n'a été vue.
    private(set) var quota: NexusQuota?

    // MARK: - Ce qui se déduit

    /// `true` **seulement** quand on sait que le compte n'est pas premium.
    var directDownloadUnavailable: Bool { account?.isPremium == false }

    /// Vrai quand le renseignement manque ou a vieilli — un compte peut
    /// devenir premium, ou cesser de l'être.
    func needsAccountRefresh(now: Date = Date()) -> Bool {
        guard let account else { return true }
        return account.isStale(now: now)
    }

    // MARK: - Ce qui l'écrit

    /// Le lot lu au lancement, hors fil principal : les trois d'un coup.
    func apply(hasApiKey: Bool, quota: NexusQuota?, account: NexusAccount?) {
        self.hasApiKey = hasApiKey
        self.quota = quota
        self.account = account
    }

    /// Le Trousseau a pris la clé. Le compte connu part avec l'ancienne : une
    /// clé neuve peut désigner un autre compte, et le garder afficherait
    /// « premium » à qui ne l'est plus.
    func keyAccepted() {
        hasApiKey = true
        account = nil
    }

    /// La clé est retirée : compte et quota partent avec elle. Rien d'autre —
    /// les mises à jour déjà relevées restent dues.
    func clearKey() {
        hasApiKey = false
        account = nil
        quota = nil
    }

    func setAccount(_ account: NexusAccount?) {
        self.account = account
    }

    func setQuota(_ quota: NexusQuota?) {
        self.quota = quota
    }
}
