import Testing
import Foundation
@testable import StarHubTHCore

/// L'état de **navigation** (chantier « vider le VM de son état publié »,
/// cadrage P8) : les poses inertes se relisent telles quelles, et les deux
/// canaux (`reportDetailFocus`, `pendingTabRequest`) suivent leur cycle de
/// vie posé-par-verbe, consommé-par-verbe — le quitus doit retomber.
///
/// La règle du changement d'onglet vit dans `TabChangePlan` (déjà testée) ;
/// ce qui se prouve ici, c'est le store comme détenteur : une consommation
/// qui n'efface pas, ou un canal qui atterrit sur la mauvaise propriété,
/// ferait survivre une demande d'ouverture jusqu'à la prochaine fiche
/// ouverte à la main — le défaut exact que les pendings existent pour
/// éviter.
@Suite struct NavigationStoreTests {

    // MARK: - Poses inertes : ce qui est posé se relit.

    @Test func poseEtRelitLesPendings() {
        let s = NavigationStore()
        s.pendingModFocus = "X"
        s.pendingTranslationFocus = "Y"
        s.pendingConfigFocus = "Z"
        s.pendingModDetailFocus = "W"
        s.pendingDetailTab = .translation
        s.pendingTranslationDiffFilter = .state(.missing)
        s.pendingLogFocus = "erreur"
        s.viewingSaveTimeline = makeSave("Farm_12345")
        s.viewingThaiMod = nil

        #expect(s.pendingModFocus == "X")
        #expect(s.pendingTranslationFocus == "Y")
        #expect(s.pendingConfigFocus == "Z")
        #expect(s.pendingModDetailFocus == "W")
        #expect(s.pendingDetailTab == .translation)
        #expect(s.pendingTranslationDiffFilter == .state(.missing))
        #expect(s.pendingLogFocus == "erreur")
        #expect(s.viewingSaveTimeline?.folderName == "Farm_12345")
    }

    // MARK: - Les deux canaux : posé par verbe, effacé par consommation.

    @Test func consommerEffaceLeCanalDuBilan() {
        let s = NavigationStore()
        s.openReportDetail(for: "ModA")
        #expect(s.reportDetailFocus == "ModA")
        s.consumeReportDetailFocus()
        #expect(s.reportDetailFocus == nil)
    }

    @Test func requestTabPoseEtConsommerEfface() {
        let s = NavigationStore()
        s.requestTab(.mods)
        #expect(s.pendingTabRequest == .mods)
        s.consumePendingTabRequest()
        #expect(s.pendingTabRequest == nil)
    }

    /// Les deux canaux sont **distincts** : poser l'un ne déborde pas sur
    /// l'autre — une requête d'onglet qui atterrirait dans le canal du bilan
    /// (ou l'inverse) ferait ouvrir une fiche au retour d'un bilan.
    @Test func lesDeuxCanauxNeDebordentPas() {
        let s = NavigationStore()
        s.requestTab(.mods)
        #expect(s.reportDetailFocus == nil)
        s.openReportDetail(for: "ModB")
        #expect(s.pendingTabRequest == .mods)
        #expect(s.reportDetailFocus == "ModB")
    }

    // MARK: - Poses à effet : la fiche

    @Test func poserUneFicheLOuvre() {
        var opened: [String] = []
        let s = NavigationStore(onModDetailOpen: { opened.append($0.folderName) })
        let mod = makeMod("Automate")
        s.setViewingModDetail(mod)
        #expect(s.viewingModDetail?.folderName == "Automate")
        #expect(opened == ["Automate"])
    }

    @Test func fermerLaFicheNouvreRien() {
        var opened: [String] = []
        let s = NavigationStore(onModDetailOpen: { opened.append($0.folderName) })
        s.setViewingModDetail(makeMod("Automate"))
        s.setViewingModDetail(nil)
        #expect(s.viewingModDetail == nil)
        #expect(opened == ["Automate"])
    }

    // MARK: - Poses à effet : l'éditeur de config (X66)

    @Test func fermerLEditeurDeConfigRescanne() {
        var closed = 0
        let s = NavigationStore(onConfigEditorClosed: { closed += 1 })
        s.setEditingModConfig(makeMod("A"))
        s.setEditingModConfig(nil)
        #expect(closed == 1)
    }

    @Test func ouvrirLEditeurDeConfigNeRescannePas() {
        var closed = 0
        let s = NavigationStore(onConfigEditorClosed: { closed += 1 })
        s.setEditingModConfig(makeMod("A"))
        #expect(closed == 0)
    }

    /// Une transition non-nil → non-nil (un autre mod) n'est pas une
    /// fermeture — et une fermeture depuis nil n'en est pas une non plus
    /// (la garde `oldValue != nil` de X66).
    @Test func changerDeModEtFermerDepuisNilNeRescannePas() {
        var closed = 0
        let s = NavigationStore(onConfigEditorClosed: { closed += 1 })
        s.setEditingModConfig(nil)
        s.setEditingModConfig(makeMod("A"))
        s.setEditingModConfig(makeMod("B"))
        #expect(closed == 0)
        s.setEditingModConfig(nil)
        #expect(closed == 1)
    }

    // MARK: - Poses à effet : l'inventaire de sauvegarde

    @Test func poserUneSauvegardeVideLinventairePuisCharge() {
        let items = [InventoryItem(slotIndex: 0, itemId: "0", name: "Pomme",
                                   stack: 3, isObject: false)]
        let save = makeSave("Farm_A")
        var pendingDone: (([InventoryItem]) -> Void)?
        let s = NavigationStore(loadInventory: { asked, done in
            #expect(asked.id == save.id)
            pendingDone = done
        })
        s.inventoryToEdit = [InventoryItem(slotIndex: 1, itemId: "1", name: "Vieux",
                                           stack: 99, isObject: false)]
        s.setEditingSave(save)
        // Avant la fin de la lecture : vide — jamais le contenu de la
        // sauvegarde précédente.
        #expect(s.inventoryToEdit.isEmpty)
        pendingDone?(items)
        #expect(s.inventoryToEdit == items)
        #expect(s.editingSave?.id == "Farm_A")
    }

    /// Garde anti-course : le résultat d'une lecture périmée (l'utilisateur
    /// a changé de sauvegarde pendant que le gros fichier se lisait)
    /// n'atterrit jamais.
    @Test func linventairePerimeEstEcarter() {
        let a = makeSave("Farm_A")
        let b = makeSave("Farm_B")
        var dones: [(id: String, done: ([InventoryItem]) -> Void)] = []
        let s = NavigationStore(loadInventory: { asked, done in
            dones.append((asked.id, done))
        })
        s.setEditingSave(a)
        s.setEditingSave(b)
        // La lecture de A revient (hors fil, plus tard) alors que B est
        // affiché : elle est écartée.
        guard let lateDone = dones.first(where: { $0.id == "Farm_A" })?.done else {
            Issue.record("la lecture de A n'a jamais été lancée")
            return
        }
        lateDone([InventoryItem(slotIndex: 0, itemId: "0", name: "DeA",
                                stack: 1, isObject: false)])
        #expect(s.inventoryToEdit.isEmpty)
        #expect(s.editingSave?.id == "Farm_B")
    }

    /// Le cas voisin : la lecture de la sauvegarde **affichée** atterrit —
    /// un garde trop large écarterait aussi celle-là.
    @Test func linventaireFraisAtterrit() {
        let items = [InventoryItem(slotIndex: 0, itemId: "0", name: "DeB",
                                   stack: 2, isObject: false)]
        let a = makeSave("Farm_A")
        let b = makeSave("Farm_B")
        var dones: [(id: String, done: ([InventoryItem]) -> Void)] = []
        let s = NavigationStore(loadInventory: { asked, done in
            dones.append((asked.id, done))
        })
        s.setEditingSave(a)
        s.setEditingSave(b)
        guard let doneB = dones.first(where: { $0.id == "Farm_B" })?.done else {
            Issue.record("la lecture de B n'a jamais été lancée")
            return
        }
        doneB(items)
        #expect(s.inventoryToEdit == items)
    }

    @Test func fermerLaSauvegardeVideSansCharger() {
        var loadCalls = 0
        let s = NavigationStore(loadInventory: { _, _ in loadCalls += 1 })
        s.setEditingSave(makeSave("Farm_A"))
        // Un inventaire affiché au moment de la fermeture : poser nil doit
        // le vider — sinon l'éditeur fermé laisse un inventaire orphelin
        // prêt à être montré pour la prochaine sauvegarde, avant son
        // propre chargement.
        s.inventoryToEdit = [InventoryItem(slotIndex: 0, itemId: "0", name: "X",
                                           stack: 1, isObject: false)]
        s.setEditingSave(nil)
        #expect(s.editingSave == nil)
        #expect(s.inventoryToEdit.isEmpty)
        #expect(loadCalls == 1)
    }

    @Test func poserNilSansClosureNeRienCasse() {
        let s = NavigationStore()
        s.setViewingModDetail(makeMod("A"))
        s.setViewingModDetail(nil)
        s.setEditingModConfig(nil)
        s.setEditingSave(nil)
        #expect(s.viewingModDetail == nil)
    }

    // MARK: - Fixtures

    private func makeMod(_ name: String) -> ModItem {
        ModItem(uniqueId: "id.\(name)", name: name, folderName: name, version: "1.0",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: true, dependencies: [], children: nil,
                languages: ["en"])
    }

    private func makeSave(_ folderName: String) -> SaveGameInfo {
        SaveGameInfo(
            folderName: folderName,
            fileURL: URL(fileURLWithPath: "/tmp/\(folderName)"),
            lastModified: Date(timeIntervalSince1970: 0),
            playerName: "P", farmName: "F", favoriteThing: "T",
            money: 500, spouse: "", maxHealth: 100, maxStamina: 270,
            goldenWalnuts: 0, qiGems: 0, clubCoins: 0, totalMoneyEarned: 0,
            year: 2, season: 1, day: 3, whichFarm: 0)
    }
}
