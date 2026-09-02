import Testing
import Foundation
@testable import StarHubTHCore

/// File FIFO des téléchargements Nexus. Le contrat testé ici est celui du
/// ViewModel : un clic répété ne duplique pas (il rafraîchit la clé), deux
/// fichiers distincts du même mod passent tous les deux, et l'ordre
/// d'arrivée tient jusqu'au drainage.
///
/// Les appels `mutating` sont hissés hors de `#expect` : la macro capture
/// la valeur pour son diagnostic et la fige en immuable.
@Suite
struct NexusDownloadQueueTests {
    private func nxm(modId: Int, fileId: Int, key: String = "k1",
                     game: String = "stardewvalley") -> NexusDownloadQueue.Entry {
        .init(modId: modId, fileId: fileId, game: game, key: key, expires: nil)
    }

    @Test func dequeueFollowsArrivalOrder() {
        var queue = NexusDownloadQueue()
        queue.enqueue(nxm(modId: 191, fileId: 1))
        queue.enqueue(nxm(modId: 505, fileId: 3))
        let first = queue.dequeue()?.modId
        let second = queue.dequeue()?.modId
        let third = queue.dequeue()
        #expect(first == 191)
        #expect(second == 505)
        #expect(third == nil)
    }

    @Test func repeatedClickOnSameFileRefreshesKeyInsteadOfDuplicating() {
        var queue = NexusDownloadQueue()
        queue.enqueue(nxm(modId: 191, fileId: 1, key: "old"))
        // Second clic sur le même fichier : le lien re-cliqué porte une clé
        // plus fraîche — c'est elle qui doit survivre, sans doublon.
        let addedOnRepeat = queue.enqueue(nxm(modId: 191, fileId: 1, key: "fresh"))
        let count = queue.entries.count
        let survivingKey = queue.dequeue()?.key
        #expect(!addedOnRepeat)
        #expect(count == 1)
        #expect(survivingKey == "fresh")
    }

    @Test func twoFilesOfTheSameModBothStayQueued() {
        var queue = NexusDownloadQueue()
        queue.enqueue(nxm(modId: 191, fileId: 1))
        queue.enqueue(nxm(modId: 191, fileId: 2))
        // Le voisin qui ne doit PAS fusionner : même mod, autre fichier,
        // autre demande.
        #expect(queue.entries.count == 2)
    }

    @Test func sameFileOnAnotherGameDomainIsADifferentRequest() {
        var queue = NexusDownloadQueue()
        queue.enqueue(nxm(modId: 191, fileId: 1, game: "stardewvalley"))
        queue.enqueue(nxm(modId: 191, fileId: 1, game: "skyrim"))
        #expect(queue.entries.count == 2)
    }

    @Test func inAppRequestsDeduplicateToo() {
        var queue = NexusDownloadQueue()
        queue.enqueue(.init(modId: 8828, fileId: nil, game: "stardewvalley",
                            key: nil, expires: nil))
        let addedOnRepeat = queue.enqueue(.init(modId: 8828, fileId: nil,
                                                game: "stardewvalley",
                                                key: nil, expires: nil))
        #expect(!addedOnRepeat)
        #expect(queue.entries.count == 1)
    }

    @Test func emptyQueueDequeuesNothing() {
        var queue = NexusDownloadQueue()
        let nothing = queue.dequeue()
        #expect(nothing == nil)
        #expect(queue.isEmpty)
    }
}
