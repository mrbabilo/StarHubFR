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

    /// Mesuré : 43 clés SMAPI `smapi/mod-data/<uid>/…` sur Zofia.
    @Test("La forme SMAPI smapi/mod-data/uid/… résout vers l'uid")
    func smapiModDataKeysResolve() {
        let s = SaveFingerprintScan(modDataKeys: [
            "smapi/mod-data/Kedi.VPP/essai": 3,
        ])
        let r = SaveFingerprintResolution.resolve(s, modIDs: ["Kedi.VPP"])
        #expect(r["Kedi.VPP"]?.modDataKeys == 3)
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

    // MARK: - Aide

    /// Les fragments proviennent du vrai producteur (le jeu) — copiés du
    /// save réel, réduits aux champs porteurs.
    private func fixture(_ raw: String) -> Data {
        Data(raw.utf8)
    }

    private func scan(_ data: Data) -> SaveFingerprintScan {
        guard let scan = SaveFingerprintScanner.scan(data) else {
            Issue.record("XML de fixture illisible")
            return SaveFingerprintScan()
        }
        return scan
    }
}
