import Testing
import Foundation
@testable import StarHubTHCore

struct InstalledTranslationTests {
    private let t0 = Date(timeIntervalSince1970: 1_787_595_034)

    private func translation(host: String = "Parchment", modId: Int = 50233,
                             version: String = "1.1.0", updatedAt: Date? = nil,
                             files: [String] = ["i18n/fr.json"],
                             replaced: [String: String] = [:]) -> InstalledTranslation {
        InstalledTranslation(hostFolderName: host, nexusModId: modId,
                             nexusName: "Parchment - Fishing Log - Francais",
                             version: version, updatedAt: updatedAt ?? t0,
                             installedAt: t0, files: files, replacedFiles: replaced)
    }

    @Test func aTranslationIsFoundBackByItsHost() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation())
        #expect(registry.translation(forHost: "Parchment")?.nexusModId == 50233)
        #expect(registry.translation(forHost: "Autre") == nil)
    }

    /// Une seule traduction par mod : la seconde recouvrirait la première sur
    /// le disque, et on ne saurait plus quoi rendre en désinstallant.
    @Test func recordingASecondTranslationReplacesTheFirst() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(modId: 1))
        registry.record(translation(modId: 2))
        #expect(registry.byHost.count == 1)
        #expect(registry.translation(forHost: "Parchment")?.nexusModId == 2)
    }

    /// Oublier rend ce qu'on savait : c'est cette valeur qui dit quels fichiers
    /// retirer et lesquels remettre en place.
    @Test func forgettingHandsBackWhatWasKnown() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(files: ["i18n/fr.json", "assets/x.png"],
                                    replaced: ["i18n/fr.json": "Backups/…/fr.json"]))
        let forgotten = registry.forget(host: "Parchment")
        #expect(forgotten?.files == ["i18n/fr.json", "assets/x.png"])
        #expect(forgotten?.replacedFiles["i18n/fr.json"] == "Backups/…/fr.json")
        #expect(registry.translation(forHost: "Parchment") == nil)
    }

    @Test func forgettingSomethingUnknownIsHarmless() {
        var registry = InstalledTranslationRegistry()
        #expect(registry.forget(host: "Jamais vu") == nil)
    }

    /// **Sur les dates, jamais sur les numéros de version.** Mesuré sur des
    /// traductions réelles : beaucoup reprennent le numéro du mod traduit, ou
    /// ne le bougent pas d'une version à l'autre.
    @Test func anUpdateIsJudgedOnDates() {
        let installed = t0
        #expect(InstalledTranslationRegistry.isNewer(t0.addingTimeInterval(86400), than: installed))
        #expect(!InstalledTranslationRegistry.isNewer(t0, than: installed))
        #expect(!InstalledTranslationRegistry.isNewer(t0.addingTimeInterval(-86400), than: installed))
    }

    /// Une date manquante d'un côté ou de l'autre ne conclut à rien : mieux
    /// vaut ne rien annoncer qu'annoncer une mise à jour qui n'existe pas.
    @Test func aMissingDateAnnouncesNothing() {
        #expect(!InstalledTranslationRegistry.isNewer(nil, than: t0))
        #expect(!InstalledTranslationRegistry.isNewer(t0, than: nil))
        #expect(!InstalledTranslationRegistry.isNewer(nil, than: nil))
    }

    /// Le registre traverse un enregistrement : c'est une trace qu'on relira
    /// des mois plus tard, quand la traduction devra être désinstallée.
    @Test func theRegistrySurvivesAnEncodeDecodeRoundTrip() throws {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(replaced: ["i18n/fr.json": "ailleurs"]))
        let data = try JSONEncoder().encode(registry)
        #expect(try JSONDecoder().decode(InstalledTranslationRegistry.self, from: data) == registry)
    }

    /// La clé est le nom **logique** du dossier : mettre le mod en pause le
    /// préfixe d'un point sur le disque, mais la traduction reste la sienne.
    @Test func aPausedHostKeepsItsTranslation() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(host: "Parchment"))
        #expect(registry.translation(forHost: "Parchment") != nil)
        #expect(registry.translation(forHost: ".Parchment") == nil)
    }

    // MARK: - Greffes (plusieurs par mod)

    private func addon(_ name: String, nexusId: Int = 0, host: String = "ItemBags",
                       at day: Int = 0) -> InstalledTranslation {
        InstalledTranslation(hostFolderName: host, nexusModId: nexusId, nexusName: name,
                             version: "1", updatedAt: nil,
                             installedAt: Date(timeIntervalSince1970: TimeInterval(day) * 86400),
                             files: ["assets/Modded Bags/\(name).json"])
    }

    /// **Le format d'avant les greffes doit se relire.** Exiger `addonsByHost`
    /// ferait échouer tout le décodage, et l'utilisateur perdrait le seul moyen
    /// de retirer les traductions déjà posées.
    @Test func aRegistryWrittenBeforeAddonsStillDecodes() throws {
        let old = """
        {"byHost":{"FishingLogbook":{"hostFolderName":"FishingLogbook","nexusModId":50233,
        "nexusName":"FishingLogbook - FR","version":"1.1.0","installedAt":770000000,
        "files":["i18n/fr.json"],"replacedFiles":{}}}}
        """
        let registry = try JSONDecoder().decode(InstalledTranslationRegistry.self,
                                                from: Data(old.utf8))
        #expect(registry.translation(forHost: "FishingLogbook")?.nexusModId == 50233)
        #expect(registry.addonsByHost.isEmpty)
    }

    /// Un mod reçoit **plusieurs** greffes : rien ne les fait se recouvrir,
    /// elles déposent des fichiers différents.
    @Test func aModCanCarrySeveralAddons() {
        var registry = InstalledTranslationRegistry()
        registry.recordAddon(addon("Utility Bags", at: 1))
        registry.recordAddon(addon("Sword and Sorcery Bags", at: 2))
        #expect(registry.addons(forHost: "ItemBags").count == 2)
        // La plus récente en tête.
        #expect(registry.addons(forHost: "ItemBags").first?.nexusName == "Sword and Sorcery Bags")
    }

    /// Redéposer le même lot met la ligne à jour, il n'en crée pas une seconde
    /// qui prétendrait qu'il est installé deux fois.
    @Test func redepositingTheSameAddonReplacesIt() {
        var registry = InstalledTranslationRegistry()
        registry.recordAddon(addon("Utility Bags", at: 1))
        registry.recordAddon(addon("utility bags", at: 5))
        let addons = registry.addons(forHost: "ItemBags")
        #expect(addons.count == 1)
        #expect(addons.first?.installedAt == Date(timeIntervalSince1970: 5 * 86400))
    }

    /// L'identifiant Nexus l'emporte sur le nom quand les deux le portent : un
    /// auteur qui renomme son lot ne doit pas en créer un second.
    @Test func theNexusIdIdentifiesAnAddonBeforeItsName() {
        var registry = InstalledTranslationRegistry()
        registry.recordAddon(addon("Utility Bags", nexusId: 37381, at: 1))
        registry.recordAddon(addon("Utility Bags Redux", nexusId: 37381, at: 2))
        #expect(registry.addons(forHost: "ItemBags").count == 1)
        #expect(registry.addons(forHost: "ItemBags").first?.nexusName == "Utility Bags Redux")
    }

    /// Un hôte qui ne porte plus de greffe quitte le registre : le garder ferait
    /// répondre « ce mod a des greffes » à tort.
    @Test func aHostWithNoAddonLeftIsDropped() {
        var registry = InstalledTranslationRegistry()
        let bag = addon("Utility Bags")
        registry.recordAddon(bag)
        #expect(registry.forgetAddon(bag)?.nexusName == "Utility Bags")
        #expect(registry.addonsByHost["ItemBags"] == nil)
        #expect(registry.forgetAddon(bag) == nil)
    }

    /// Greffes et traduction cohabitent sur le même mod sans se voir.
    @Test func anAddonDoesNotDisturbTheTranslation() {
        var registry = InstalledTranslationRegistry()
        registry.record(InstalledTranslation(
            hostFolderName: "ItemBags", nexusModId: 1, nexusName: "FR", version: "1",
            updatedAt: nil, installedAt: Date(), files: ["i18n/fr.json"]))
        registry.recordAddon(addon("Utility Bags"))
        #expect(registry.translation(forHost: "ItemBags")?.nexusName == "FR")
        #expect(registry.addons(forHost: "ItemBags").count == 1)
    }

    /// **Rattacher ne doit pas déclarer la ligne à jour par construction.**
    /// Retenir la date Nexus du résultat reviendrait à la comparer à elle-même :
    /// aucune mise à jour ne pourrait jamais apparaître. C'est la date du dépôt
    /// qui fait foi — tout ce que Nexus a publié depuis est plus récent.
    @Test func linkingKeepsTheDepositDateSoUpdatesCanStillShow() {
        let deposited = Date(timeIntervalSince1970: 1_000_000)
        let publishedSince = Date(timeIntervalSince1970: 2_000_000)
        #expect(InstalledTranslationRegistry.isNewer(publishedSince, than: deposited))
        // Le piège évité : la date du résultat comparée à elle-même.
        #expect(!InstalledTranslationRegistry.isNewer(publishedSince, than: publishedSince))
    }

    /// **Redéposer une version plus récente doit reconnaître l'ancienne.**
    /// Le nom du fichier change d'une version à l'autre — `-1-0-0-` devient
    /// `-1-1-0-` — mais l'identifiant Nexus, lui, ne bouge pas. Sans cela les
    /// anciens fichiers restaient sur le disque et une seconde ligne
    /// s'ajoutait.
    @Test func aNewerDownloadOfTheSameAddonIsRecognised() {
        var registry = InstalledTranslationRegistry()
        registry.recordAddon(addon("Utility Bags-37381-1-0-0-1757199288", at: 1))
        registry.recordAddon(addon("Utility Bags-37381-1-1-0-1799999999", at: 2))
        let addons = registry.addons(forHost: "ItemBags")
        #expect(addons.count == 1)
        #expect(addons.first?.nexusName == "Utility Bags-37381-1-1-0-1799999999")
    }

    /// Deux greffes réellement différentes ne se confondent pas, même quand
    /// leurs noms se ressemblent au début.
    @Test func twoDifferentAddonsStayApart() {
        var registry = InstalledTranslationRegistry()
        registry.recordAddon(addon("ItemBags for All Cornucopia-33439-1-0-0-1745271524", at: 1))
        registry.recordAddon(addon("ItemBags for Wildflour-31000-2-0-2-1762148429", at: 2))
        #expect(registry.addons(forHost: "ItemBags").count == 2)
    }

    /// **La ligne d'avant et la ligne d'après doivent se reconnaître.** Depuis
    /// que le dépôt lit l'identifiant dans le nom du fichier
    /// (`NexusArchiveName`), une greffe redéposée en porte un — alors que celle
    /// déjà au registre a été posée sans. La comparaison stricte par
    /// identifiant ne s'applique que si **les deux** en ont un ; ici c'est le
    /// nom qui doit encore trancher, sinon les fichiers de l'ancienne resteraient
    /// sur le disque et une seconde ligne s'ajouterait.
    @Test func anAddonRecordedBeforeIdsWereLearnedIsStillRecognised() {
        var registry = InstalledTranslationRegistry()
        registry.recordAddon(addon("Utility Bags-37381-1-0-0-1757199288", nexusId: 0, at: 1))
        registry.recordAddon(addon("Utility Bags-37381-1-1-0-1799999999", nexusId: 37381, at: 2))
        let addons = registry.addons(forHost: "ItemBags")
        #expect(addons.count == 1)
        #expect(addons.first?.nexusModId == 37381)
    }

    /// L'identifiant appris ne rapproche pas deux greffes qui n'ont rien à voir :
    /// une seule des deux en porte un, et leurs noms diffèrent.
    @Test func aLearnedIdDoesNotMergeTwoUnrelatedAddons() {
        var registry = InstalledTranslationRegistry()
        registry.recordAddon(addon("ItemBags for All Cornucopia-33439-1-0-0-1745271524",
                                   nexusId: 0, at: 1))
        registry.recordAddon(addon("ItemBags for Wildflour-31000-2-0-2-1762148429",
                                   nexusId: 31000, at: 2))
        #expect(registry.addons(forHost: "ItemBags").count == 2)
    }

    // MARK: - A3-T6 — déclaration manuelle d'une traduction posée hors de l'app

    private func decl(modId: Int = 50233, name: String = "Parchment - FR") -> DeclaredTranslation {
        DeclaredTranslation(nexusModId: modId, nexusName: name,
                           version: "1.1.0", updatedAt: t0, declaredAt: t0)
    }

    /// La déclaration est retrouvée par son hôte, comme une traduction
    /// installée — mais par le canal séparé `declaredTranslation(forHost:)`.
    /// Une installation et une déclaration peuvent cohabiter sur le même mod.
    @Test func aDeclaredTranslationIsFoundByItsHost() {
        var registry = InstalledTranslationRegistry()
        registry.declare(decl(), forHost: "Parchment")
        #expect(registry.declaredTranslation(forHost: "Parchment")?.nexusModId == 50233)
        #expect(registry.declaredTranslation(forHost: "Other") == nil)
        #expect(registry.translation(forHost: "Parchment") == nil)
    }

    /// Une seule déclaration par mod : une seconde écrase la première. C'est
    /// volontaire — l'utilisateur peut avoir trouvé le bon identifiant après
    /// coup, et l'ancien ne resterait qu'à embrouiller.
    @Test func aSecondDeclarationReplacesTheFirst() {
        var registry = InstalledTranslationRegistry()
        registry.declare(decl(modId: 1), forHost: "Parchment")
        registry.declare(decl(modId: 2, name: "Parchment - FR v2"), forHost: "Parchment")
        #expect(registry.declaredTranslation(forHost: "Parchment")?.nexusModId == 2)
    }

    /// Oublier une déclaration rend `true` quand il y avait quelque chose, et
    /// `false` sinon — utile au journal pour distinguer un oubli d'une
    /// absence.
    @Test func undeclaringReturnsWhetherSomethingWasForgotten() {
        var registry = InstalledTranslationRegistry()
        registry.declare(decl(), forHost: "Parchment")
        let first = registry.undeclare(forHost: "Parchment")
        #expect(first)
        let second = registry.undeclare(forHost: "Parchment")
        #expect(!second)
        let third = registry.undeclare(forHost: "Jamais vu")
        #expect(!third)
    }

    /// Une installation et une déclaration coexistent sur le même hôte sans
    /// s'écraser — elles répondent à deux questions différentes
    /// (l'app a-t-elle posé ? l'utilisateur a-t-il déclaré ?).
    @Test func aDeclarationCoexistsWithAnInstall() {
        var registry = InstalledTranslationRegistry()
        registry.record(translation(host: "Parchment"))
        registry.declare(decl(modId: 99999), forHost: "Parchment")
        #expect(registry.translation(forHost: "Parchment")?.nexusModId == 50233)
        #expect(registry.declaredTranslation(forHost: "Parchment")?.nexusModId == 99999)
    }

    /// **Les anciens registres (avant A3-T6) doivent toujours se décoder.**
    /// Exiger `declaredTranslations` ferait échouer le décodage, et
    /// l'utilisateur perdrait le seul moyen de désinstaller ses anciennes
    /// traductions posées par l'app.
    @Test func aRegistryWrittenBeforeDeclarationsStillDecodes() throws {
        let old = """
        {"byHost":{"FishingLogbook":{"hostFolderName":"FishingLogbook","nexusModId":50233,
        "nexusName":"FishingLogbook - FR","version":"1.1.0","installedAt":770000000,
        "files":["i18n/fr.json"],"replacedFiles":{}}},
        "addonsByHost":{}}
        """
        let registry = try JSONDecoder().decode(InstalledTranslationRegistry.self,
                                                from: Data(old.utf8))
        #expect(registry.translation(forHost: "FishingLogbook")?.nexusModId == 50233)
        #expect(registry.declaredTranslations.isEmpty)
    }

    /// Le registre complet (installation + greffes + déclaration) survit à un
    /// aller-retour JSON.
    @Test func theRegistryWithDeclarationsSurvivesARoundTrip() throws {
        var registry = InstalledTranslationRegistry()
        registry.record(translation())
        registry.recordAddon(addon("Utility Bags"))
        registry.declare(decl(modId: 99999), forHost: "Other")
        let data = try JSONEncoder().encode(registry)
        let back = try JSONDecoder().decode(InstalledTranslationRegistry.self, from: data)
        #expect(back == registry)
    }

    // MARK: - Store (persistance)

    private var storeFile: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalledTranslationStoreTests-\(UUID().uuidString)")
            .appendingPathComponent("installed_translations.json")
    }

    /// Chaque écriture pose la **même** génération au fichier et à son
    /// `.bak` — le motif du registre d'install UserDefaults (primary + backup,
    /// même blob aux deux emplacements). Le backup de la génération courante
    /// restaure tout ; celui de la génération précédente ne rendrait que
    /// l'avant-dernier état.
    @Test func storeSaveKeepsABackupCopyOfTheSameGeneration() throws {
        let file = storeFile
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        var registry = InstalledTranslationRegistry()
        registry.record(translation())
        #expect(InstalledTranslationStore.save(registry, to: file))

        let backup = file.appendingPathExtension("bak")
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(InstalledTranslationStore.load(from: backup) == registry)
    }

    /// Un registre corrompu ne rend plus un magasin **vide** en silence :
    /// c'est la seule trace de ce qui a été déposé, et sa perte rend toute
    /// désinstallation impossible. Le `.bak` reprend la main, et se **promeut**
    /// au fichier principal pour que le chargement suivant soit sain.
    @Test func storeLoadRestoresTheBackupWhenThePrimaryIsCorrupt() throws {
        let file = storeFile
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        var registry = InstalledTranslationRegistry()
        registry.record(translation())
        #expect(InstalledTranslationStore.save(registry, to: file))

        try Data("pas du json".utf8).write(to: file)
        #expect(InstalledTranslationStore.load(from: file) == registry)
        // Promotion prouvée par le fichier lui-même : le principal redevient
        // lisible, le prochain chargement ne repassera plus par le backup.
        let promoted = try JSONDecoder().decode(InstalledTranslationRegistry.self,
                                                from: Data(contentsOf: file))
        #expect(promoted == registry)
    }

    /// Sans fichier du tout, le magasin reste vide — premier lancement, jamais
    /// une erreur.
    @Test func storeLoadWithoutAnyFileIsEmpty() {
        let file = storeFile
        #expect(InstalledTranslationStore.load(from: file) == InstalledTranslationRegistry())
    }
}
