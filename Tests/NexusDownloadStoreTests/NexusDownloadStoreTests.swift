import Testing
import Foundation
@testable import StarHubTHCore

/// Le téléchargement Nexus en vol : son cycle, la barre qui se tait pendant
/// l'attente, l'annulation qui ne conclut pas, et le débit qui ne survit pas
/// à son transfert.
///
/// Le jugement « suis-je occupé ? » n'est pas ici : il vit dans
/// `NexusDownloadFlow`, qui voit aussi la feuille d'installation.
@Suite struct NexusDownloadStoreTests {

    private func entry(_ modId: Int) -> NexusDownloadQueue.Entry {
        .init(modId: modId, fileId: nil, game: "stardewvalley", key: nil, expires: nil)
    }

    // MARK: - Le cycle

    /// L'ouverture allume les deux témoins et **laisse la barre muette** :
    /// les deux appels d'API qui résolvent le lien n'ont rien à mesurer, et
    /// une barre à zéro mentirait sur ce qui se passe.
    @Test func openingLightsTheFlagsButNotTheBar() {
        let s = NexusDownloadStore()
        s.beginDownload(modId: 42)
        #expect(s.isDownloading)
        #expect(s.downloadingModId == 42)
        #expect(s.progress == nil)
    }

    @Test func progressAppearsOnlyOnceBytesArrive() {
        let s = NexusDownloadStore()
        s.beginDownload(modId: 42)
        s.noteProgress(received: 500, expected: 1000, modId: 42)
        #expect(s.progress?.bytesReceived == 500)
        #expect(s.progress?.nexusModId == 42)
    }

    /// La remise au repos emporte les trois témoins **et** la tâche : les
    /// oublier condamnait le bouton pour la session.
    @Test func endingPutsEverythingBackToRest() {
        let s = NexusDownloadStore()
        s.beginDownload(modId: 42)
        s.noteProgress(received: 10, expected: 100, modId: 42)
        s.endDownload()
        #expect(s.isDownloading == false)
        #expect(s.downloadingModId == nil)
        #expect(s.progress == nil)
        // `inFlight` n'est pas observable : il est `private`, et
        // `NexusFileDownload` est `final` — donc pas de doublure. Sa remise à
        // `nil` n'a qu'un point d'écriture, ici même.
    }

    // MARK: - Annuler n'est pas conclure

    /// `URLSession` rapporte l'annulation par le chemin d'échec, et c'est lui
    /// qui appelle `endDownload()`. Conclure ici aussi laisserait l'état au
    /// repos pendant qu'un transfert continue.
    @Test func cancellingDoesNotPutTheStateBackToRest() {
        let s = NexusDownloadStore()
        s.beginDownload(modId: 42)
        s.noteProgress(received: 10, expected: 100, modId: 42)
        s.cancel()
        #expect(s.isDownloading)                 // toujours en vol
        #expect(s.downloadingModId == 42)
        #expect(s.progress != nil)
    }

    // MARK: - Le débit ne survit pas à son transfert

    /// Sans remise à zéro, le transfert suivant hérite des octets du
    /// précédent — rien ne casse, le chiffre est seulement faux.
    ///
    /// ⚠️ L'horloge est **injectée**, sans quoi ce test est creux : deux
    /// relevés posés dans la même milliseconde ne rendent aucun débit, et il
    /// passait alors avec *et* sans la remise à zéro.
    @Test func theRateDoesNotCarryOverToTheNextDownload() {
        let s = NexusDownloadStore()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        s.beginDownload(modId: 1)
        // Deux relevés espacés d'une seconde : 5 Mo/s, mesurable.
        s.noteProgress(received: 0, expected: 10_000_000, modId: 1, now: t0)
        s.noteProgress(received: 5_000_000, expected: 10_000_000, modId: 1,
                       now: t0.addingTimeInterval(1))
        #expect(s.progress?.bytesPerSecond != nil, "le débit devait être mesurable ici")
        s.endDownload()

        s.beginDownload(modId: 2)
        // Premier relevé du transfert neuf, une seconde plus tard : un seul
        // échantillon ne donne aucun débit. S'il en donne un, c'est que les
        // échantillons du transfert précédent sont encore là.
        s.noteProgress(received: 1, expected: 10_000_000, modId: 2,
                       now: t0.addingTimeInterval(2))
        #expect(s.progress?.bytesPerSecond == nil)
    }

    /// Ouvrir un second transfert ne doit pas laisser la barre du premier :
    /// un store neuf a déjà `progress == nil`, donc seul ce cas-ci prouve que
    /// l'ouverture la remet à zéro.
    @Test func openingASecondDownloadClearsTheBarOfTheFirst() {
        let s = NexusDownloadStore()
        s.beginDownload(modId: 1)
        s.noteProgress(received: 900, expected: 1000, modId: 1)
        s.beginDownload(modId: 2)
        #expect(s.progress == nil)
        #expect(s.downloadingModId == 2)
    }

    // MARK: - La file

    @Test func aQueuedDownloadComesBackOutAndLeavesTheQueueEmpty() {
        let s = NexusDownloadStore()
        #expect(s.dequeue() == nil)                 // rien en attente
        #expect(s.enqueue(entry(7)))
        #expect(s.dequeue() == entry(7))
        #expect(s.dequeue() == nil)                 // et elle s'est vidée
    }

    /// La même demande deux fois ne fait pas deux téléchargements.
    @Test func theSameRequestIsNotQueuedTwice() {
        let s = NexusDownloadStore()
        #expect(s.enqueue(entry(7)))
        #expect(s.enqueue(entry(7)) == false)
    }
}
