import Foundation
import Testing
@testable import StarHubTHCore

/// A1-T8/A1-T6 — le scanneur et la résolution d'empreintes de sauvegarde.
///
/// Les fragments XML sont copiés de `Zofia_443716371` (mesure du 2026-09-23) :
/// un objet porte `name` **et** `itemId` namespacés identiques et compte une
/// fois ; un bâtiment porte `buildingType` ; une clé `modData` est
/// `key`>`string` ; les listes de butin mettent leurs références dans des
/// `<string>` isolés qui ne sont pas des instances.
@Suite struct SaveFingerprintTests {

    // MARK: - Le scanneur

    /// **Le test central** : name + itemId portent le MÊME objet — compter
    /// les deux champs doublerait (815 objets Alchemistry se seraient lus
    /// 1 630 dans la sonde avant déduplication).
    @Test("Un objet namespacé compte une instance, même porté par name et itemId")
    func countsOneInstancePerObject() {
        let xml = fixture(
            "<SaveGame><items>"
                + "<Item xsi:type=\"Object\"><isLostItem>false</isLostItem><category>-81</category>"
                + "<name>Morghoula.AlchemistryCP_MeteorCap</name><parentSheetIndex>4</parentSheetIndex>"
                + "<itemId>Morghoula.AlchemistryCP_MeteorCap</itemId><quality>4</quality></Item>"
                + "</items></SaveGame>")
        let scan = SaveFingerprintScanner.scan(xml)
        #expect(scan?.objects == ["Morghoula.AlchemistryCP_MeteorCap": 1])
        #expect(scan?.buildings.isEmpty == true)
        #expect(scan?.modDataKeys.isEmpty == true)
    }

    /// Mesuré sur le parc : 1 922 `itemId` namespacés pour 1 648 `name` —
    /// des objets n'ont QUE l'id namespacé (nom affiché vanilla).
    @Test("Un objet dont seul itemId est namespacé compte")
    func countsWhenOnlyItemIdIsNamespaced() {
        let xml = fixture(
            "<SaveGame><Item><name>Ketchup</name>"
                + "<itemId>Morghoula.AlchemistryCP_TomatoKetchup</itemId></Item></SaveGame>")
        #expect(
            self.scan(xml).objects == ["Morghoula.AlchemistryCP_TomatoKetchup": 1])
    }

    @Test("Un objet dont seul name est namespacé compte")
    func countsWhenOnlyNameIsNamespaced() {
        let xml = fixture(
            "<SaveGame><Item><name>Lumisteria.MtVapius_Porchini</name>"
                + "<itemId>(O)257</itemId></Item></SaveGame>")
        #expect(self.scan(xml).objects == ["Lumisteria.MtVapius_Porchini": 1])
    }

    @Test("Un objet vanilla ne compte pas")
    func ignoresVanillaObjects() {
        let xml = fixture(
            "<SaveGame><Item xsi:type=\"MeleeWeapon\"><name>Lava Katana</name>"
                + "<itemId>9</itemId></Item></SaveGame>")
        #expect(SaveFingerprintScanner.scan(xml)?.objects.isEmpty == true)
    }

    /// Les listes de butin (mesurées : 667 références namespacées hors
    /// modData sur Zofia) sont des références, pas des instances.
    @Test("Une référence dans une liste de butin ne compte pas comme objet")
    func lootListReferencesAreNotObjects() {
        let xml = fixture(
            "<SaveGame><string>(O)404,(O)Morghoula.AlchemistryCP_ForestWisp,(O)420"
                + "</string></SaveGame>")
        let scan = SaveFingerprintScanner.scan(xml)
        #expect(scan?.objects.isEmpty == true)
        #expect(scan?.modDataKeys.isEmpty == true)
    }

    @Test("Un bâtiment namespacé compte une instance de bâtiment")
    func countsNamespacedBuilding() {
        let xml = fixture(
            "<SaveGame><buildings><Building>"
                + "<buildingType>Bindicle.Dayswork_Office</buildingType>"
                + "</Building></buildings></SaveGame>")
        #expect(SaveFingerprintScanner.scan(xml)?.buildings
            == ["Bindicle.Dayswork_Office": 1])
    }

    /// Structure réelle : `<item><key><string>clé</string></key><value>…`.
    @Test("Une clé modData namespacée compte")
    func countsNamespacedModDataKey() {
        let xml = fixture(
            "<SaveGame><modDataDictionary><item>"
                + "<key><string>structureBuilt_Bindicle.Dayswork_Office</string></key>"
                + "<value><int>6</int></value></item>"
                + "<item><key><string>eventSeen_7001</string></key>"
                + "<value><int>7</int></value></item></modDataDictionary></SaveGame>")
        #expect(SaveFingerprintScanner.scan(xml)?.modDataKeys
            == ["structureBuilt_Bindicle.Dayswork_Office": 1])
    }

    @Test("Des objets identiques s'empilent ; des objets distincts coexistent")
    func stacksAndCoexists() {
        let xml = fixture(
            "<SaveGame>"
                + "<Item><name>Morghoula.AlchemistryCP_ForestWisp</name>"
                + "<itemId>Morghoula.AlchemistryCP_ForestWisp</itemId></Item>"
                + "<Item><name>Morghoula.AlchemistryCP_ForestWisp</name>"
                + "<itemId>Morghoula.AlchemistryCP_ForestWisp</itemId></Item>"
                + "<Item><name>Morghoula.AlchemistryCP_HellfireBolete</name>"
                + "<itemId>Morghoula.AlchemistryCP_HellfireBolete</itemId></Item>"
                + "</SaveGame>")
        let scan = SaveFingerprintScanner.scan(xml)
        #expect(scan?.objects["Morghoula.AlchemistryCP_ForestWisp"] == 2)
        #expect(scan?.objects["Morghoula.AlchemistryCP_HellfireBolete"] == 1)
    }

    /// Un XML illisible ne vaut pas « zéro empreinte » — l'appelant ne
    /// doit pas cacher ce résultat (piège du cache d'octets étrangers).
    @Test("Un XML illisible retourne nil, pas un scan vide")
    func brokenXMLReturnsNil() {
        #expect(SaveFingerprintScanner.scan(Data("pas du xml".utf8)) == nil)
    }

    // MARK: - La résolution

    /// Les trois formes mesurées (zéro ambiguïté sur 1 125 ids du parc).
    @Test("Résolution : identique, préfixe underscore, sous-clé point")
    func resolvesThreeShapes() {
        let s = SaveFingerprintScan(
            objects: ["Morghoula.AlchemistryCP": 1, "Morghoula.AlchemistryCP_MeteorCap": 2],
            buildings: [:],
            modDataKeys: ["Kedi.VPP.TalentPointCount": 3])
        let r = SaveFingerprintResolution.resolve(
            s, modIDs: ["Morghoula.AlchemistryCP", "Kedi.VPP"])
        #expect(r["Morghoula.AlchemistryCP"]?.objects == 3)
        #expect(r["Morghoula.AlchemistryCP"]?.modDataKeys == 0)
        #expect(r["Kedi.VPP"]?.modDataKeys == 3)
    }

    /// `A.B_C` et `A.B` peuvent coexister comme ids du parc : l'empreinte
    /// `A.B_C_X` appartient à `A.B_C`, pas à `A.B`.
    @Test("Le préfixe le plus long gagne")
    func longestPrefixWins() {
        let s = SaveFingerprintScan(objects: ["A.B_C_D": 1])
        let r = SaveFingerprintResolution.resolve(s, modIDs: ["A.B", "A.B_C"])
        #expect(r["A.B_C"]?.objects == 1)
        #expect(r["A.B"] == nil)
    }

    /// Mesuré sur Zofia : 138 clés de jeu portent l'uid en suffixe —
    /// `structureBuilt_…` (1), `firstVisit_…` (63), `eventSeen_…` (39)… La
    /// règle est générique (fonction en un mot de lettres avant le premier
    /// underscore), jamais une liste codée en dur qui divergerait du jeu.
    @Test("Une clé de jeu fonction_uid résout vers le mod du suffixe")
    func gameFunctionKeysResolve() {
        let s = SaveFingerprintScan(modDataKeys: [
            "structureBuilt_Bindicle.Dayswork_Office": 1,
            "eventSeen_7001": 2,
        ])
        let r = SaveFingerprintResolution.resolve(s, modIDs: ["Bindicle.Dayswork"])
        #expect(r["Bindicle.Dayswork"]?.modDataKeys == 1)
    }

    /// Mesuré sur Zofia (2026-09-23) : 35 clés `smapi/mod-data/<uid>/…`,
    /// 26 mods. SMAPI écrit l'uid **en minuscules**, et un uid peut n'avoir
    /// aucun point (`Cropgenics`). La clé passe par le vrai `scan()` : un
    /// scan construit à la main cachait que le scanneur refusait le `/`.
    @Test("La forme SMAPI smapi/mod-data/uid/…, lue par scan(), résout vers l'uid")
    func smapiModDataKeysResolve() {
        let xml = fixture(
            "<SaveGame><modData><item>"
                + "<key><string>smapi/mod-data/spacechase0.spacecore/skills</string></key>"
                + "<value><string>x</string></value></item>"
                + "<item><key><string>smapi/mod-data/cropgenics/state</string></key>"
                + "<value><string>x</string></value></item>"
                + "<item><key><string>smapi/mod-data/thalethegreat.wallettools/"
                + "legacy-migrated-thalethegreat.walletautopetter-walletautopetter.state"
                + "</string></key><value><string>x</string></value></item>"
                + "</modData></SaveGame>")
        let r = SaveFingerprintResolution.resolve(
            scan(xml),
            modIDs: ["spacechase0.SpaceCore", "Cropgenics",
                     "ThaleTheGreat.WalletTools", "thalethegreat.walletautopetter"])
        #expect(r["spacechase0.SpaceCore"]?.modDataKeys == 1)
        #expect(r["Cropgenics"]?.modDataKeys == 1)
        // L'uid est le segment entre les deux `/`, pas ce que cite la suite.
        #expect(r["ThaleTheGreat.WalletTools"]?.modDataKeys == 1)
        #expect(r["thalethegreat.walletautopetter"] == nil)
    }

    /// Mesuré sur Zofia (2026-09-23) : la convention `<uid>/<clé>` porte la
    /// masse des clés modData (`mistyspring.ItemExtensions/IsFTM` ×1 703,
    /// `larvuk.AdvancedFruitTreeFramework/…` ×1 648), avec des uids sans
    /// point (`Cropgenics`) ; les salles du Centre (`Pantry/…`) ont la même
    /// forme et ne sont à aucun mod.
    @Test("La forme uid/clé, lue par scan(), résout vers l'uid du segment de tête")
    func uidSlashKeysResolve() {
        let xml = fixture(
            "<SaveGame><modData><item>"
                + "<key><string>mistyspring.ItemExtensions/IsFTM</string></key>"
                + "<value><string>true</string></value></item>"
                + "<item><key><string>Cropgenics/Fertility</string></key>"
                + "<value><string>1</string></value></item>"
                + "<item><key><string>DIGUS.ANIMALHUSBANDRYMOD/age</string></key>"
                + "<value><string>1</string></value></item>"
                + "<item><key><string>Pantry/0</string></key>"
                + "<value><string>x</string></value></item>"
                + "</modData></SaveGame>")
        let r = SaveFingerprintResolution.resolve(
            scan(xml),
            modIDs: ["mistyspring.ItemExtensions", "Cropgenics",
                     "Digus.AnimalHusbandryMod"])
        #expect(r["mistyspring.ItemExtensions"]?.modDataKeys == 1)
        #expect(r["Cropgenics"]?.modDataKeys == 1)
        #expect(r["Digus.AnimalHusbandryMod"]?.modDataKeys == 1)
        #expect(r.count == 3)
    }

    @Test("Un uid cité hors de la tête d'une clé à / n'attribue rien")
    func uidOutsideSlashHeadAttributesNothing() {
        let xml = fixture(
            "<SaveGame><modData><item>"
                + "<key><string>autre/mod-data/Cropgenics/x</string></key>"
                + "<value><string>x</string></value></item></modData></SaveGame>")
        let r = SaveFingerprintResolution.resolve(scan(xml), modIDs: ["Cropgenics"])
        #expect(r.isEmpty)
    }

    /// Mesuré : `Lumisteria.MtVapius_*` (mod absent) ne doit attribuer ses
    /// 133 empreintes à personne.
    @Test("Une empreinte orpheline n'attribue rien")
    func orphanFingerprintAttributesNothing() {
        let s = SaveFingerprintScan(objects: ["Lumisteria.MtVapius_BlackChanterelle": 5])
        let r = SaveFingerprintResolution.resolve(
            s, modIDs: ["Morghoula.AlchemistryCP"])
        #expect(r.isEmpty)
    }

    @Test("Somme complète par mod : objets, bâtiments et modData ensemble")
    func sumsAllFamilies() {
        let s = SaveFingerprintScan(
            objects: ["Bindicle.Dayswork_Tool": 3],
            buildings: ["Bindicle.Dayswork_Office": 1],
            modDataKeys: ["structureBuilt_Bindicle.Dayswork_Office": 1])
        let r = SaveFingerprintResolution.resolve(s, modIDs: ["Bindicle.Dayswork"])
        #expect(r["Bindicle.Dayswork"] == FingerprintCounts(
            objects: 3, buildings: 1, modDataKeys: 1))
    }

    // MARK: - Le rapport de bascule

    /// A1-T8 — le rapport ne porte que les ids du plan : une save qui
    /// n'abrite que les empreintes d'un autre mod reste hors du compte.
    @Test("Le rapport totalise par save les mods du plan seulement")
    func reportTotalsOnlyPlanModsPerSave() throws {
        let dir = try TemporaryDirectory()
        try fixture("<SaveGame><Item><name>Zofia</name>"
            + "<itemId>Morghoula.AlchemistryCP_MeteorCap</itemId></Item>"
            + "<Item><itemId>Lumisteria.MtVapius_BlackChanterelle</itemId></Item></SaveGame>")
            .write(to: dir.url.appendingPathComponent("Save1_1"))
        try fixture("<SaveGame><Item><name>Autre</name>"
            + "<itemId>Lumisteria.MtVapius_BlackChanterelle</itemId></Item></SaveGame>")
            .write(to: dir.url.appendingPathComponent("Save2_2"))
        let report = SaveFingerprintReport.scanSaves(
            at: [("Save1_1", dir.url.appendingPathComponent("Save1_1")),
                 ("Save2_2", dir.url.appendingPathComponent("Save2_2"))],
            modIDs: ["Morghoula.AlchemistryCP"])
        #expect(report.perSave.count == 1)
        #expect(report.perSave["Save1_1"] == FingerprintCounts(objects: 1))
    }

    /// Le plan d'un pack porte plusieurs mods : leurs empreintes s'additionnent.
    @Test("Le rapport additionne les empreintes de tous les mods du plan")
    func reportSumsAllPlanMods() throws {
        let dir = try TemporaryDirectory()
        try fixture("<SaveGame><Item><name>Zofia</name>"
            + "<itemId>A.B_Thing</itemId></Item>"
            + "<Building><buildingType>C.D_House</buildingType></Building>"
            + "<modDataDictionary><item><key><string>K.VP.Count</string></key>"
            + "<value><int>1</int></value></item></modDataDictionary></SaveGame>")
            .write(to: dir.url.appendingPathComponent("Save1_1"))
        let report = SaveFingerprintReport.scanSaves(
            at: [("Save1_1", dir.url.appendingPathComponent("Save1_1"))],
            modIDs: ["A.B", "C.D", "K.VP"])
        #expect(report.perSave["Save1_1"] == FingerprintCounts(
            objects: 1, buildings: 1, modDataKeys: 1))
    }

    /// Une save illisible n'entre pas dans le rapport — l'alerte chiffre ce
    /// qu'elle lit, elle ne prétend pas à un audit (c'est A1-T9).
    @Test("Une save illisible est absente du rapport")
    func unreadableSaveIsAbsentFromReport() throws {
        let dir = try TemporaryDirectory()
        try fixture("<SaveGame><Item><name>Zofia</name>"
            + "<itemId>A.B_Thing</itemId></Item></SaveGame>")
            .write(to: dir.url.appendingPathComponent("Good_1"))
        try Data("pas du xml".utf8).write(to: dir.url.appendingPathComponent("Bad_2"))
        let report = SaveFingerprintReport.scanSaves(
            at: [("Good_1", dir.url.appendingPathComponent("Good_1")),
                 ("Bad_2", dir.url.appendingPathComponent("Bad_2"))],
            modIDs: ["A.B"])
        #expect(report.perSave["Good_1"]?.objects == 1)
        #expect(report.perSave["Bad_2"] == nil)
    }

    @Test("Le tri met les saves les plus chargées d'abord ; hiddenCount compte la retenue")
    func sortingAndHiddenCount() {
        let report = SaveFingerprintReport(perSave: [
            "Petite": FingerprintCounts(objects: 2),
            "Grosse": FingerprintCounts(objects: 757),
            "Moyenne": FingerprintCounts(objects: 100, modDataKeys: 1),
        ])
        let order = report.sortedEntries.map(\.name)
        #expect(order == ["Grosse", "Moyenne", "Petite"])
        #expect(report.hiddenCount(beyond: 3) == 0)
        #expect(report.hiddenCount(beyond: 2) == 1)
        #expect(report.sortedEntries[0].counts.total == 757)
    }

    // MARK: - Aide

    /// Structure réelle de Zofia : le `<name>` d'une GameLocation est un
    /// enfant direct, après ses `terrainFeatures` et ses personnages.
    @Test("Une GameLocation namespacée compte un lieu, pas un objet")
    func namespacedLocationCountsAsLocation() {
        let xml = fixture(
            "<SaveGame><locations><GameLocation><characters><NPC>"
                + "<name>Wildflour.NooksCrannies_Hermit</name></NPC></characters>"
                + "<name>Wildflour.NooksCrannies_BerryGrove</name>"
                + "</GameLocation></locations></SaveGame>")
        let s = scan(xml)
        #expect(s.locations == ["Wildflour.NooksCrannies_BerryGrove": 1])
        #expect(s.objects.isEmpty)
    }

    @Test("Un arbre de mod compte un arbre ; un arbre vanilla, rien")
    func namespacedTreesCount() {
        let xml = fixture(
            "<SaveGame><terrainFeatures>"
                + "<TerrainFeature><growthStage>8</growthStage>"
                + "<treeType>Wildflour.SASS_Candy_Button_Tree</treeType></TerrainFeature>"
                + "<TerrainFeature><growthStage>4</growthStage>"
                + "<treeId>Lumisteria.MtVapius_GrapeSapling</treeId></TerrainFeature>"
                + "<TerrainFeature><treeType>3</treeType></TerrainFeature>"
                + "</terrainFeatures></SaveGame>")
        let s = scan(xml)
        #expect(s.trees == ["Wildflour.SASS_Candy_Button_Tree": 1,
                            "Lumisteria.MtVapius_GrapeSapling": 1])
        #expect(s.objects.isEmpty)
    }

    @Test("Un NPC namespacé n'est pas un objet")
    func namespacedNPCIsNotAnObject() {
        let xml = fixture(
            "<SaveGame><characters><NPC><name>PeacefulEnd.Campgrounds.Characters.Caretaker</name>"
                + "</NPC></characters></SaveGame>")
        #expect(scan(xml).objects.isEmpty)
    }

    @Test("Lieux et arbres se résolvent vers leur mod")
    func locationsAndTreesResolve() {
        let s = SaveFingerprintScan(
            locations: ["Wildflour.NooksCrannies_BerryGrove": 1],
            trees: ["Wildflour.SASS_Candy_Button_Tree": 2])
        let r = SaveFingerprintResolution.resolve(
            s, modIDs: ["Wildflour.NooksCrannies", "Wildflour.SASS"])
        #expect(r["Wildflour.NooksCrannies"] == FingerprintCounts(locations: 1))
        #expect(r["Wildflour.SASS"] == FingerprintCounts(trees: 2))
    }

    /// Les fragments proviennent du vrai producteur (le jeu) — copiés du
    /// save réel, réduits aux champs porteurs.
    private func fixture(_ raw: String) -> Data {
        Data(raw.utf8)
    }

    /// Dossier temporaire jetable par test — jamais le vrai Application
    /// Support (582 exécutions polluées avant l'injection des managers).
    private struct TemporaryDirectory {
        let url: URL
        init() throws {
            url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("SaveFingerprintTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func scan(_ data: Data) -> SaveFingerprintScan {
        guard let scan = SaveFingerprintScanner.scan(data) else {
            Issue.record("XML de fixture illisible")
            return SaveFingerprintScan()
        }
        return scan
    }
}

/// A1-T6 — la fiche de sauvegarde : quels mods **en pause** y ont laissé du
/// contenu. Les scans sont construits à la main : le scanneur a ses propres
/// tests ci-dessus, ici on éprouve le croisement avec l'état du parc.
@Suite struct SavePausedFootprintsTests {

    private func mod(_ id: String, enabled: Bool, folder: String? = nil) -> ModItem {
        ModItem(uniqueId: id, name: id, folderName: folder ?? id, version: "1",
                author: "", description: "", nexusUrl: "", nexusModId: "",
                isEnabled: enabled, dependencies: [])
    }

    @Test("Un mod en pause porteur d'empreintes est rapporté, un actif non")
    func reportsPausedOnly() {
        let scan = SaveFingerprintScan(objects: ["P.X_Thing": 3, "A.Y_Thing": 5])
        let entries = SavePausedFootprints.entries(
            scan: scan, mods: [mod("P.X", enabled: false), mod("A.Y", enabled: true)])
        #expect(entries == [PausedModFootprint(
            folderName: "P.X", name: "P.X", counts: FingerprintCounts(objects: 3))])
    }

    /// Résoudre contre les seuls ids en pause ferait retomber `A.B_C_Thing`
    /// (propriété du mod actif `A.B_C`) sur `A.B`, en pause.
    @Test("Le préfixe long d'un mod actif n'est pas attribué au court en pause")
    func activeLongerPrefixWins() {
        let scan = SaveFingerprintScan(objects: ["A.B_C_Thing": 4])
        let entries = SavePausedFootprints.entries(
            scan: scan, mods: [mod("A.B", enabled: false), mod("A.B_C", enabled: true)])
        #expect(entries.isEmpty)
    }

    /// Le parc réel porte des doublons d'installation (Swim, deux fois) :
    /// une copie active suffit à ce que le contenu ne dorme pas.
    @Test("Un id porté aussi par une copie active n'est pas rapporté")
    func duplicateWithActiveCopyIsSilent() {
        let scan = SaveFingerprintScan(objects: ["S.W_Suit": 2])
        let entries = SavePausedFootprints.entries(
            scan: scan,
            mods: [mod("S.W", enabled: false, folder: "Swim old"),
                   mod("S.W", enabled: true, folder: "Swim")])
        #expect(entries.isEmpty)
    }

    @Test("Deux copies en pause du même id ne font qu'une rangée")
    func duplicatePausedCopiesReportOnce() {
        let scan = SaveFingerprintScan(objects: ["S.W_Suit": 2])
        let entries = SavePausedFootprints.entries(
            scan: scan,
            mods: [mod("S.W", enabled: false, folder: "Swim old"),
                   mod("S.W", enabled: false, folder: "Swim")])
        #expect(entries.count == 1)
    }

    /// 111 mods du parc réel n'ont pas d'identifiant : un id vide ne doit
    /// rien s'attribuer (le préfixe "_" couvrirait n'importe quelle clé).
    @Test("Un mod sans identifiant n'est jamais rapporté")
    func emptyIdIsExcluded() {
        let scan = SaveFingerprintScan(modDataKeys: ["_hidden": 1, "": 1])
        let entries = SavePausedFootprints.entries(
            scan: scan, mods: [mod("", enabled: false, folder: "Sans id")])
        #expect(entries.isEmpty)
    }

    /// Les composants héritent du `isEnabled` du pack au scan : un pack en
    /// pause rend ses composants, chacun avec ses empreintes.
    @Test("Un composant de pack en pause est rapporté sous son dossier")
    func pausedPackComponentIsReported() {
        let pack = ModItem(uniqueId: "", name: "Pack", folderName: "Pack", version: "1",
                       author: "", description: "", nexusUrl: "", nexusModId: "",
                       isEnabled: false, dependencies: [],
                       children: [mod("K.CP", enabled: false, folder: "Pack/[CP] K")],
                       isGroup: true)
        let scan = SaveFingerprintScan(buildings: ["K.CP_Barn": 1])
        let entries = SavePausedFootprints.entries(scan: scan, mods: [pack])
        #expect(entries.map(\.folderName) == ["Pack/[CP] K"])
        #expect(entries.first?.counts == FingerprintCounts(buildings: 1))
    }

    @Test("Les plus chargés d'abord")
    func sortedByTotalDescending() {
        let scan = SaveFingerprintScan(objects: ["L.A_x": 1, "H.B_x": 9])
        let entries = SavePausedFootprints.entries(
            scan: scan, mods: [mod("L.A", enabled: false), mod("H.B", enabled: false)])
        #expect(entries.map(\.name) == ["H.B", "L.A"])
    }
}

/// A1-T8 — la suspension de bascule : annuler clôture sans renommer,
/// confirmer reprend, et une seconde sortie (Esc après le clic) ne fait rien.
@MainActor
@Suite struct SaveFingerprintPauseStoreTests {
    private let mod = ModItem(
        uniqueId: "A.B", name: "A.B", folderName: "A.B", version: "1",
        author: "", description: "", nexusUrl: "", nexusModId: "",
        isEnabled: true, dependencies: [])
    private let report = SaveFingerprintReport(
        perSave: ["Zofia": FingerprintCounts(objects: 1)])

    @Test("Annuler clôture sans reprendre la bascule")
    func cancelAbortsWithoutResuming() {
        let store = SaveFingerprintPauseStore()
        var resumed = 0, aborted = 0
        store.suspend(subject: .mod(mod), report: report,
                      resume: { resumed += 1 }, abort: { aborted += 1 })
        store.cancel()
        #expect(resumed == 0)
        #expect(aborted == 1)
        #expect(store.pending == nil)
    }

    @Test("Confirmer reprend une fois ; la fermeture qui suit ne fait rien")
    func confirmResumesOnce() {
        let store = SaveFingerprintPauseStore()
        var resumed = 0, aborted = 0
        store.suspend(subject: .mod(mod), report: report,
                      resume: { resumed += 1 }, abort: { aborted += 1 })
        store.confirm()
        store.cancel()
        #expect(resumed == 1)
        #expect(aborted == 0)
    }

    @Test("Une suspension de profil porte le nom du profil")
    func profileSubjectCarriesProfileName() {
        let store = SaveFingerprintPauseStore()
        store.suspend(subject: .profile(name: "Hiver"), report: report,
                      resume: {}, abort: {})
        #expect(store.pending?.subject == .profile(name: "Hiver"))
    }

    @Test("Occupé tant qu'une suspension attend ; libre après la sortie")
    func busyWhileSuspended() {
        let store = SaveFingerprintPauseStore()
        #expect(!store.isBusy)
        store.suspend(subject: .mods(count: 12), report: report,
                      resume: {}, abort: {})
        #expect(store.isBusy)
        #expect(store.pending?.subject == .mods(count: 12))
        store.cancel()
        #expect(!store.isBusy)
    }
}
