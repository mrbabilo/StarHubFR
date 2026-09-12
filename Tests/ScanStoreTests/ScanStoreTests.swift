import Testing
import Foundation
@testable import StarHubTHCore

/// L'état du domaine Scan (cadrage §3, domaine 8). Ce qui se prouve ici :
/// **toute pose du parc prévient les consommateurs** — y compris une pose
/// identique, fidèle au `didSet` d'origine qui ne comparait pas — et la
/// sérialisation de la mesure des poids (une passe à la fois, demande
/// rejouée, mesure ratée qui n'efface pas pendant qu'une passe est en
/// route). Le scanner, son cache mtime et son verrou vivent dans
/// `ModScanner` (déjà testé) ; les cascades elles-mêmes (catégories,
/// couverture, raccourcis) sont du câblage de l'app.
@Suite struct ScanStoreTests {

    // MARK: - Le parc et sa cascade

    @Test func poserLeParcPrevientLesConsommateurs() {
        var notified: [[ModItem]] = []
        let s = ScanStore()
        s.wireEffects(onModsChanged: { notified.append($0) })
        s.setMods([makeMod("Automate")])
        #expect(s.mods.map(\.folderName) == ["Automate"])
        #expect(notified.count == 1)
        #expect(notified[0].map(\.folderName) == ["Automate"])
    }

    /// Une pose identique reste une demande de recalcul — le `didSet`
    /// d'origine se déclenchait sur toute affectation, pas sur changement.
    @Test func poserLeMemeParcPrevientAussi() {
        var notified = 0
        let s = ScanStore()
        s.wireEffects(onModsChanged: { _ in notified += 1 })
        let parc = [makeMod("Automate")]
        s.setMods(parc)
        s.setMods(parc)
        #expect(notified == 2)
    }

    @Test func setDuplicateIndexPose() {
        let s = ScanStore()
        s.setDuplicateIndex(ModDuplicateIndex(folders: ["swim": ["Swim", ".Swim"]],
                                              activeCopies: ["swim": 2]))
        #expect(s.duplicateIndex.folders["swim"] == ["Swim", ".Swim"])
    }

    @Test func progressionEtPoidsSeRelisent() {
        let s = ScanStore()
        s.scanProgress = ScanProgress(done: 3, total: 10, currentName: "X")
        #expect(s.scanProgress?.done == 3)
        #expect(s.modsFolderSizes == nil)
        #expect(s.isMeasuringModsFolder == false)
    }

    // MARK: - La mesure des poids : une passe à la fois, demande rejouée

    @Test func uneSeulePasseALaFois() {
        let s = ScanStore()
        #expect(s.beginSizeMeasure() == false)
        #expect(s.beginSizeMeasure() == true)
    }

    /// Une demande arrivée pendant la passe n'est pas perdue : `end` la
    /// signale **une fois**, puis le drapeau se consomme.
    @Test func laDemandeEnVolEstRejoueeUneSeuleFois() {
        let s = ScanStore()
        #expect(s.beginSizeMeasure() == false)
        #expect(s.beginSizeMeasure() == true)
        #expect(s.endSizeMeasure() == true)
        #expect(s.endSizeMeasure() == false)
    }

    @Test func finDePasseRendLeVerrou() {
        let s = ScanStore()
        #expect(s.beginSizeMeasure() == false)
        #expect(s.endSizeMeasure() == false)
        #expect(s.beginSizeMeasure() == false)
    }

    // MARK: - La mesure des poids : ce qui atterrit

    /// Une mesure ratée (dossier absent) pendant qu'une nouvelle passe est
    /// en route n'efface pas la précédente — le pied de barre garde un
    /// chiffre vraisemblable plutôt que de clignoter.
    @Test func uneMesureRateeNeffacePasPendantUnePasse() {
        let s = ScanStore()
        s.setSizeMeasureResult(makeSizes(), again: false)
        s.beginSizeMeasure()
        s.setSizeMeasureResult(nil, again: true)
        #expect(s.modsFolderSizes != nil)
        #expect(s.isMeasuringModsFolder == true)
    }

    /// Le cas voisin : sans passe en route, une mesure ratée **efface** —
    /// il n'y a rien à mesurer (jeu non désigné), garder un vieux chiffre
    /// mentirait.
    @Test func uneMesureRateeSansPasseEnRouteEfface() {
        let s = ScanStore()
        s.setSizeMeasureResult(makeSizes(), again: false)
        s.setSizeMeasureResult(nil, again: false)
        #expect(s.modsFolderSizes == nil)
    }

    @Test func laMesureRejoueeAnnonceLaTraversee() {
        let s = ScanStore()
        s.setSizeMeasureRunning(true)
        #expect(s.isMeasuringModsFolder == true)
        s.setSizeMeasureResult(makeSizes(), again: false)
        #expect(s.isMeasuringModsFolder == false)
    }

    // MARK: - Fixtures

    private func makeMod(_ name: String) -> ModItem {
        ModItem(uniqueId: "id.\(name)", name: name, folderName: name, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: true, dependencies: [], children: nil,
                languages: ["en"])
    }

    private func makeSizes() -> ModsFolderSizes {
        ModsFolderSizes(byPhysicalFolder: ["Automate": 1_000], totalBytes: 1_000,
                        pausedBytes: 0, availableBytes: nil,
                        measuredAt: Date(timeIntervalSince1970: 0))
    }
}
