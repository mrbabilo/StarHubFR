import Testing
@testable import StarHubTHCore

struct AlertStoreTests {
    @Test func showSetsMessageAndPresents() {
        let store = AlertStore()
        store.show("Erreur de lecture")
        #expect(store.message == "Erreur de lecture")
        #expect(store.shown)
    }

    @Test func dismissingKeepsTheMessageButHides() {
        // SwiftUI repose le binding à `false` quand l'utilisateur ferme :
        // le message reste posé — la fermeture ne l'efface pas.
        let store = AlertStore()
        store.show("Erreur")
        store.shown = false
        #expect(store.message == "Erreur")
        #expect(!store.shown)
    }

    @Test func showingAgainReplacesTheMessage() {
        let store = AlertStore()
        store.show("Premier")
        store.shown = false
        store.show("Second")
        #expect(store.message == "Second")
        #expect(store.shown)
    }
}
