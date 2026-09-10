import Testing
import Foundation
@testable import StarHubTHCore

/// La persistance du registre a trois mécanismes de sûreté — copie de secours à
/// chaque écriture, restauration sur corruption, reconstruction depuis le
/// disque — qui n'ont jamais eu de test : ils vivaient dans le ViewModel, où
/// rien n'est vérifiable. Ce sont eux qui décident si l'app sait encore quand un
/// mod a été installé, donc si elle annonce des mises à jour qui n'existent pas.
///
/// Les tests injectent un domaine `UserDefaults` jetable : toucher au domaine
/// standard ferait écrire ces tests dans les préférences réelles de
/// l'utilisateur.
struct InstalledModRegistryStoreTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)

    private func freshDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Domaine neuf **avec la migration v2 déjà faite** : c'est l'état courant
    /// d'une installation, et sans ce drapeau la première synchronisation
    /// purgerait le registre avant de faire quoi que ce soit d'autre.
    private func migratedDefaults() -> UserDefaults {
        let d = freshDefaults()
        d.set(true, forKey: UDKey.registryMigrationV2Done)
        return d
    }

    private func mod(_ folder: String, version: String = "1.0",
                     uniqueId: String? = nil) -> ModItem {
        ModItem(uniqueId: uniqueId ?? "id.\(folder)", name: folder, folderName: folder,
                version: version, author: "", description: "", nexusUrl: "",
                nexusModId: "", isEnabled: true, dependencies: [], children: nil)
    }

    private func record(_ version: String, _ at: Date) -> InstalledModRecord {
        InstalledModRecord(version: version, installedAt: at)
    }

    private func write(_ map: [String: InstalledModRecord],
                       to key: String, in defaults: UserDefaults) {
        defaults.set(try! JSONEncoder().encode(map), forKey: key)
    }

    private func read(_ key: String, in defaults: UserDefaults) -> [String: InstalledModRecord]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([String: InstalledModRecord].self, from: data)
    }

    // MARK: - 1. Chaîne de chargement : la clé principale

    @Test func aValidPrimaryIsReturnedAsIs() {
        let defaults = migratedDefaults()
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistry, in: defaults)
        let store = InstalledModRegistryStore(defaults: defaults)
        #expect(store.all()["Automate"] == record("1.0", t0))
    }

    @Test func anUnknownFolderHasNoInstallDate() {
        #expect(InstalledModRegistryStore(defaults: migratedDefaults())
            .installedDate(for: "Jamais vu") == nil)
    }

    // MARK: - 2. Chaîne de chargement : le secours

    @Test func aCorruptPrimaryFallsBackToTheBackup() {
        let defaults = migratedDefaults()
        defaults.set(Data("pas du json".utf8), forKey: UDKey.installedModRegistry)
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistryBackup, in: defaults)

        let store = InstalledModRegistryStore(defaults: defaults)
        #expect(store.all()["Automate"] == record("1.0", t0))
    }

    @Test func aRecoveredBackupIsPromotedBackToThePrimary() {
        // Sans la promotion, chaque chargement suivant repasserait par le
        // chemin de corruption — et la principale resterait illisible.
        let defaults = migratedDefaults()
        defaults.set(Data("pas du json".utf8), forKey: UDKey.installedModRegistry)
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistryBackup, in: defaults)

        _ = InstalledModRegistryStore(defaults: defaults).all()

        #expect(read(UDKey.installedModRegistry, in: defaults)?["Automate"] == record("1.0", t0))
    }

    @Test func anAbsentPrimaryWithAValidBackupIsRecoveredToo() {
        // « Absente » et « corrompue » ne suivent pas le même chemin dans le
        // code : la seconde purge d'abord. Les deux doivent aboutir au secours.
        let defaults = migratedDefaults()
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistryBackup, in: defaults)
        #expect(InstalledModRegistryStore(defaults: defaults).all()["Automate"] == record("1.0", t0))
    }

    // MARK: - 3. Chaîne de chargement : les deux perdues

    @Test func bothCorruptYieldsAnEmptyRegistryAndPurgesBothKeys() {
        let defaults = migratedDefaults()
        defaults.set(Data("pas du json".utf8), forKey: UDKey.installedModRegistry)
        defaults.set(Data("pas du json non plus".utf8), forKey: UDKey.installedModRegistryBackup)

        let store = InstalledModRegistryStore(defaults: defaults)
        #expect(store.all().isEmpty)
        // Les blobs corrompus sont purgés : ils bloqueraient sinon les
        // chargements suivants sans jamais pouvoir être réparés.
        #expect(defaults.data(forKey: UDKey.installedModRegistry) == nil)
        #expect(defaults.data(forKey: UDKey.installedModRegistryBackup) == nil)
    }

    // MARK: - 4. Toute écriture double le blob

    @Test func writingPutsTheSameBlobOnBothKeys() {
        let defaults = migratedDefaults()
        let store = InstalledModRegistryStore(defaults: defaults)
        store.replaceAll(["Automate": record("1.0", t0)])

        let primary = defaults.data(forKey: UDKey.installedModRegistry)
        let backup = defaults.data(forKey: UDKey.installedModRegistryBackup)
        #expect(primary != nil)
        #expect(primary == backup)
    }

    @Test func aSyncAlsoWritesTheBackup() {
        // La copie de secours ne vaut que si elle suit *toutes* les écritures,
        // pas seulement les remplacements explicites.
        let defaults = migratedDefaults()
        let store = InstalledModRegistryStore(defaults: defaults)
        _ = store.sync(scannedMods: [mod("Automate")],
                       modsFolderWasReadable: true,
                       anchorStore: ModVersionAnchorStore(defaults: defaults),
                       suggestedVersions: [:],
                       now: t0)
        #expect(read(UDKey.installedModRegistryBackup, in: defaults)?["Automate"]?.version == "1.0")
    }

    @Test func aMutationSurvivesAFreshStoreOnTheSameDefaults() {
        // Un magasin neuf : c'est ce que fait un redémarrage de l'app.
        let defaults = migratedDefaults()
        InstalledModRegistryStore(defaults: defaults)
            .mutate { $0["Automate"] = record("2.0", t1) }
        #expect(InstalledModRegistryStore(defaults: defaults)
            .installedDate(for: "Automate") == t1)
    }

    @Test func mutateReturnsTheValueItsBodyProduces() {
        // C'est ce qui a remplacé la boîte à un élément dont le ViewModel se
        // servait pour faire échapper un booléen d'une closure `inout`.
        let store = InstalledModRegistryStore(defaults: migratedDefaults())
        let count = store.mutate { registry -> Int in
            registry["Automate"] = self.record("1.0", self.t0)
            return registry.count
        }
        #expect(count == 1)
    }

    // MARK: - 5. Migration v2 : purge une fois, drapeau après la purge

    @Test func theFirstSyncWipesARegistryBuiltOnStaleFolderDates() {
        let defaults = freshDefaults() // drapeau absent : la migration doit jouer
        write(["Ancien": record("1.0", t0)], to: UDKey.installedModRegistry, in: defaults)

        let store = InstalledModRegistryStore(defaults: defaults)
        let report = store.sync(scannedMods: [mod("Automate")],
                                modsFolderWasReadable: true,
                                anchorStore: ModVersionAnchorStore(defaults: defaults),
                                suggestedVersions: [:],
                                now: t1)

        // L'entrée d'avant a disparu, et ce qui est vu maintenant porte
        // l'horloge de la passe, pas la date d'empaquetage d'une archive.
        #expect(store.all()["Ancien"] == nil)
        #expect(store.all()["Automate"]?.installedAt == t1)
        #expect(report.rebuiltFromDisk == 1)
        #expect(defaults.bool(forKey: UDKey.registryMigrationV2Done))
    }

    @Test func theWipeDoesNotRunTwice() {
        let defaults = freshDefaults()
        let store = InstalledModRegistryStore(defaults: defaults)
        let anchors = ModVersionAnchorStore(defaults: defaults)

        _ = store.sync(scannedMods: [mod("Automate")], modsFolderWasReadable: true,
                       anchorStore: anchors, suggestedVersions: [:], now: t0)
        let second = store.sync(scannedMods: [mod("Automate")], modsFolderWasReadable: true,
                                anchorStore: anchors, suggestedVersions: [:], now: t1)

        // La date du premier constat tient : une seconde purge la remplacerait
        // par `t1`, et l'app croirait le mod installé aujourd'hui.
        #expect(store.all()["Automate"]?.installedAt == t0)
        #expect(second.rebuiltFromDisk == 0)
    }

    @Test func anEmptyRebuildIsNotReported() {
        // Purger un registre déjà vide n'a rien reconstruit : l'annoncer ferait
        // dire à l'app qu'elle a retrouvé des mods qu'elle n'a pas vus.
        let defaults = freshDefaults()
        let report = InstalledModRegistryStore(defaults: defaults)
            .sync(scannedMods: [], modsFolderWasReadable: true,
                  anchorStore: ModVersionAnchorStore(defaults: defaults),
                  suggestedVersions: [:], now: t0)
        #expect(report.rebuiltFromDisk == 0)
    }

    // MARK: - 6. Dossiers en grâce

    @Test func aFolderInGraceKeepsItsInstallDateDespiteAVersionChange() {
        // Sa version « change » parce que la migration a retiré `nexusVersion`
        // du registre : c'est la lecture qui a changé, pas le disque.
        let defaults = migratedDefaults()
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistry, in: defaults)
        let store = InstalledModRegistryStore(defaults: defaults)
        store.setInstallDateGrace(["Automate"])

        let report = store.sync(scannedMods: [mod("Automate", version: "2.0")],
                                modsFolderWasReadable: true,
                                anchorStore: ModVersionAnchorStore(defaults: defaults),
                                suggestedVersions: [:],
                                now: t1)

        #expect(store.all()["Automate"]?.installedAt == t0)
        #expect(report.gracePreserved == 1)
    }

    @Test func theGraceListIsClearedAfterThePassThatConsumesIt() {
        let defaults = migratedDefaults()
        let store = InstalledModRegistryStore(defaults: defaults)
        store.setInstallDateGrace(["Automate"])
        _ = store.sync(scannedMods: [mod("Automate")], modsFolderWasReadable: true,
                       anchorStore: ModVersionAnchorStore(defaults: defaults),
                       suggestedVersions: [:], now: t0)
        #expect(store.installDateGrace().isEmpty)
    }

    @Test func aFolderNotInGraceIsRestamped() {
        // Le voisin du cas précédent : sans grâce, un changement de version
        // *doit* déplacer la date. Une grâce trop large perdrait cette règle.
        let defaults = migratedDefaults()
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistry, in: defaults)
        let store = InstalledModRegistryStore(defaults: defaults)

        _ = store.sync(scannedMods: [mod("Automate", version: "2.0")],
                       modsFolderWasReadable: true,
                       anchorStore: ModVersionAnchorStore(defaults: defaults),
                       suggestedVersions: [:], now: t1)

        #expect(store.all()["Automate"]?.installedAt == t1)
    }

    // MARK: - 7. Un `Mods/` illisible n'atteste aucune suppression

    @Test func anUnreadableModsFolderPrunesNeitherRegistryNorAnchors() {
        // Dossier de jeu déplacé, volume externe débranché, droits refusés : un
        // lot vide veut alors dire « on n'a rien vu », pas « il n'y a rien ».
        // Purger là-dessus viderait les 1 097 entrées du parc **et** leur copie
        // de secours, qui reçoit le même blob à la même écriture.
        let defaults = migratedDefaults()
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistry, in: defaults)
        let anchors = ModVersionAnchorStore(defaults: defaults)
        anchors.put(ModVersionAnchor(uniqueId: "id.Automate", anchoredVersion: "1.0",
                                     origin: .install, anchoredAt: t0))

        let store = InstalledModRegistryStore(defaults: defaults)
        _ = store.sync(scannedMods: [], modsFolderWasReadable: false,
                       anchorStore: anchors, suggestedVersions: [:], now: t1)

        #expect(store.all()["Automate"] != nil)
        #expect(anchors.anchor(for: "id.Automate") != nil)
    }

    @Test func areadableModsFolderDoesPruneWhatIsGone() {
        // Le voisin qui doit continuer de purger — sans lui, la réserve
        // ci-dessus se lirait comme « on ne purge plus jamais ».
        let defaults = migratedDefaults()
        write(["Parti": record("1.0", t0)], to: UDKey.installedModRegistry, in: defaults)
        let anchors = ModVersionAnchorStore(defaults: defaults)
        anchors.put(ModVersionAnchor(uniqueId: "id.Parti", anchoredVersion: "1.0",
                                     origin: .install, anchoredAt: t0))

        let store = InstalledModRegistryStore(defaults: defaults)
        _ = store.sync(scannedMods: [mod("Automate")], modsFolderWasReadable: true,
                       anchorStore: anchors, suggestedVersions: [:], now: t1)

        #expect(store.all()["Parti"] == nil)
        #expect(anchors.anchor(for: "id.Parti") == nil)
    }

    // MARK: - Packs et ancrage sur constat disque

    @Test func packComponentsAreTrackedIndividually() {
        let defaults = migratedDefaults()
        let pack = ModItem(uniqueId: "", name: "RSV", folderName: "RSV", version: "",
                           author: "", description: "", nexusUrl: "", nexusModId: "",
                           isEnabled: true, dependencies: [],
                           children: [mod("RSV/Core"), mod("RSV/Extras")], isGroup: true)
        let store = InstalledModRegistryStore(defaults: defaults)
        _ = store.sync(scannedMods: [pack], modsFolderWasReadable: true,
                       anchorStore: ModVersionAnchorStore(defaults: defaults),
                       suggestedVersions: [:], now: t0)

        #expect(Set(store.all().keys) == ["RSV/Core", "RSV/Extras"])
    }

    @Test func aModUpdatedOutsideTheAppMovesItsAnchor() {
        // Le défaut que cet ancrage répare : un mod mis à jour à la main
        // continuait d'annoncer son ancienne version, et smapi.io répondait
        // « mise à jour disponible » indéfiniment.
        let defaults = migratedDefaults()
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistry, in: defaults)
        let anchors = ModVersionAnchorStore(defaults: defaults)
        anchors.put(ModVersionAnchor(uniqueId: "id.Automate", anchoredVersion: "1.0",
                                     origin: .install, anchoredAt: t0))

        let store = InstalledModRegistryStore(defaults: defaults)
        _ = store.sync(scannedMods: [mod("Automate", version: "2.0")],
                       modsFolderWasReadable: true, anchorStore: anchors,
                       suggestedVersions: ["id.Automate": "2.0"], now: t1)

        #expect(anchors.anchor(for: "id.Automate")?.anchoredVersion == "2.0")
    }

    @Test func aFolderInGraceIsNotAnchored() {
        // Sa version change parce que la lecture a changé : l'ancrer
        // affirmerait une installation qui n'a pas eu lieu.
        let defaults = migratedDefaults()
        write(["Automate": record("1.0", t0)], to: UDKey.installedModRegistry, in: defaults)
        let anchors = ModVersionAnchorStore(defaults: defaults)
        let store = InstalledModRegistryStore(defaults: defaults)
        store.setInstallDateGrace(["Automate"])

        _ = store.sync(scannedMods: [mod("Automate", version: "2.0")],
                       modsFolderWasReadable: true, anchorStore: anchors,
                       suggestedVersions: ["id.Automate": "2.0"], now: t1)

        #expect(anchors.anchor(for: "id.Automate") == nil)
    }

    @Test func aModNeverSeenBeforeIsNotAnchoredOnItsFirstScan() {
        // Il n'a pas de version précédente : rien n'a été *constaté* changer.
        let defaults = migratedDefaults()
        let anchors = ModVersionAnchorStore(defaults: defaults)
        _ = InstalledModRegistryStore(defaults: defaults)
            .sync(scannedMods: [mod("Automate")], modsFolderWasReadable: true,
                  anchorStore: anchors, suggestedVersions: [:], now: t0)
        #expect(anchors.anchor(for: "id.Automate") == nil)
    }
}
