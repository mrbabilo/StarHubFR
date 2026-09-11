import Testing
import Foundation
@testable import StarHubTHCore

/// Les décisions de la file de téléchargement Nexus, extraites du ViewModel
/// (2026-09-11) : le créneau occupé (un prédicat qui vivait en **trois
/// exemplaires**), l'aiguillage démarrer/mettre-en-file, la classification
/// d'un résultat (annuler n'est pas une panne), et la table des messages
/// d'erreur — qui existait, elle aussi, en deux exemplaires divergents.
struct NexusDownloadFlowTests {

    private func entry(modId: Int = 191, fileId: Int? = nil) -> NexusDownloadQueue.Entry {
        .init(modId: modId, fileId: fileId, game: "stardewvalley", key: nil, expires: nil)
    }

    // MARK: - Le créneau

    /// Le créneau est occupé tant qu'un transfert court **ou** qu'une feuille
    /// d'installation attend d'être fermée : démarrer par-dessus écraserait
    /// le zip que l'utilisateur n'a pas encore installé.
    @Test func slotIsBusyWhileDownloadingOrPendingInstall() {
        #expect(!NexusDownloadFlow.isBusy(isDownloading: false, hasPendingZip: false))
        #expect(NexusDownloadFlow.isBusy(isDownloading: true, hasPendingZip: false))
        #expect(NexusDownloadFlow.isBusy(isDownloading: false, hasPendingZip: true))
        #expect(NexusDownloadFlow.isBusy(isDownloading: true, hasPendingZip: true))
    }

    // MARK: - L'aiguillage

    /// Au repos, la demande part tout de suite ; occupé, elle prend la file.
    @Test func routingStartsWhenFreeAndQueuesWhenBusy() {
        #expect(NexusDownloadFlow.route(entry(), isBusy: false) == .start(entry()))
        #expect(NexusDownloadFlow.route(entry(), isBusy: true) == .enqueue(entry()))
    }

    // MARK: - La classification d'un résultat

    /// Un succès rend le zip **et** ce que le téléchargement savait du
    /// fichier posé (X9 : identifiant + date de mise en ligne), pour que
    /// l'ancrage n'ait pas à réinventer ces faits.
    @Test func successCarriesZipAndInstallFacts() {
        let zip = URL(fileURLWithPath: "/tmp/mod.zip")
        // La fixture vient du **vrai producteur** — le décodeur de l'API —
        // plutôt que d'un init écrit à la main : un fichier construit à la
        // main décrit un état que Nexus ne rend jamais.
        let json = Data("""
        {"file_id": 7, "category_id": 1, "category_name": "MAIN",
         "version": "2.0", "mod_version": "2.0", "uploaded_timestamp": 1700000000}
        """.utf8)
        let file = try! JSONDecoder().decode(NexusModFile.self, from: json)
        let completion = NexusDownloadFlow.completion(
            for: .success(NexusDownloadOutcome(zip: zip, resolvedFile: file)), modId: 191)

        guard case .installable(let gotZip, let modId, let facts, let journal) = completion else {
            Issue.record("attendait .installable"); return
        }
        #expect(gotZip == zip)
        #expect(modId == 191)
        #expect(facts?.fileId == 7)
        #expect(journal == .plain("vm_nexus_dl_completed"))
    }

    /// Un succès **sans** fichier résolu reste installable : le zip est là,
    /// seuls les faits manquent — l'app s'abstient d'ancrer plutôt que
    /// d'inventer.
    @Test func successWithoutResolvedFileStaysInstallableWithoutFacts() {
        let completion = NexusDownloadFlow.completion(
            for: .success(NexusDownloadOutcome(zip: URL(fileURLWithPath: "/tmp/m.zip"),
                                               resolvedFile: nil)), modId: 191)
        guard case .installable(_, _, let facts, _) = completion else {
            Issue.record("attendait .installable"); return
        }
        #expect(facts == nil)
    }

    /// **Annuler n'est pas une panne** : le journal en garde la trace, mais
    /// aucune alerte ne s'ouvre sur un geste volontaire.
    @Test func cancellationJournalsWithoutAlerting() {
        let completion = NexusDownloadFlow.completion(for: .failure(.cancelled), modId: 191)
        #expect(completion == .cancelled(journal: .plain("vm_nexus_dl_cancelled")))
    }

    /// Une vraie panne alerte **et** journalise, avec le même message.
    @Test func realFailureAlertsAndJournals() {
        let completion = NexusDownloadFlow.completion(for: .failure(.rateLimited), modId: 191)
        #expect(completion == .failed(message: .plain("vm_nexus_dl_rate_limited")))
    }

    // MARK: - La table des messages — une seule, deux résolveurs

    /// Chaque erreur porte sa clé ; celles qui ont un argument le portent
    /// avec, pour que le format s'applique du côté qui résout.
    @Test func everyErrorMapsToItsKey() {
        #expect(NexusDownloadFlow.message(for: .noApiKey) == .plain("vm_nexus_dl_no_api_key"))
        #expect(NexusDownloadFlow.message(for: .noValidFile) == .plain("vm_nexus_dl_no_valid_file"))
        #expect(NexusDownloadFlow.message(for: .noDownloadLink) == .plain("vm_nexus_dl_no_link"))
        #expect(NexusDownloadFlow.message(for: .authFailed) == .plain("vm_nexus_dl_auth_failed"))
        #expect(NexusDownloadFlow.message(for: .linkExpired) == .plain("vm_nexus_dl_link_expired"))
        #expect(NexusDownloadFlow.message(for: .rateLimited) == .plain("vm_nexus_dl_rate_limited"))
        #expect(NexusDownloadFlow.message(for: .cancelled) == .plain("vm_nexus_dl_cancelled_error"))
        #expect(NexusDownloadFlow.message(for: .serverError(503))
                == .withInt("vm_nexus_dl_server_error", 503))
        #expect(NexusDownloadFlow.message(for: .requestFailed("hôte introuvable"))
                == .withText("vm_nexus_dl_request_failed", "hôte introuvable"))
    }

    /// La résolution applique le format avec le bundle que l'appelant donne —
    /// c'est ce qui permet au ViewModel d'utiliser son bundle vivant (qui
    /// suit un changement de langue en session) là où `errorDescription`
    /// passe par `NSLocalizedString`, sans pour autant deux tables.
    @Test func resolutionAppliesTheCallersBundle() {
        let bundle: (String) -> String = { key in
            ["vm_nexus_dl_rate_limited": "Trop de requêtes",
             "vm_nexus_dl_server_error": "Erreur serveur %d",
             "vm_nexus_dl_request_failed": "Échec : %@"][key] ?? key
        }
        #expect(NexusDownloadFlow.message(for: .rateLimited).resolved(bundle) == "Trop de requêtes")
        #expect(NexusDownloadFlow.message(for: .serverError(503)).resolved(bundle) == "Erreur serveur 503")
        #expect(NexusDownloadFlow.message(for: .requestFailed("DNS")).resolved(bundle) == "Échec : DNS")
    }

    /// Une clé absente du bundle se rend telle quelle plutôt que vide — un
    /// libellé manquant se voit, une chaîne vide laisse une alerte muette.
    @Test func unknownKeyRendersAsItself() {
        #expect(NexusDownloadFlow.message(for: .noApiKey).resolved { _ in "" } == "")
        #expect(NexusDownloadFlow.message(for: .noApiKey).resolved { $0 } == "vm_nexus_dl_no_api_key")
    }
}
