import Testing
import Foundation
@testable import StarHubTHCore

/// La détection de mises à jour est déléguée à smapi.io ; quand celle-ci
/// refuse de juger un mod, il reste sans verdict de **toute** source et la
/// fenêtre le tait. Preuve levée le 2026-08-27 : *Powered Automation* installé
/// en 1.0.0, publié en 1.025 sur Nexus, « has no valid versions » côté
/// smapi.io — et « tous à jour » à l'écran.
///
/// Les cas de ces tests sont **relevés sur le parc réel** (1 010 `UniqueID`,
/// 122 mods bloqués) : messages d'erreur, identifiants et versions sont ceux
/// mesurés, pas des exemples inventés.
struct NexusFallbackCheckTests {

    private func blocked(_ uniqueId: String,
                         version: String = "1.0.0",
                         keys: [String] = [],
                         meta: Int? = nil,
                         errors: [String],
                         held: NexusInstallFacts? = nil) -> NexusFallbackCheck.Blocked {
        NexusFallbackCheck.Blocked(uniqueId: uniqueId, name: uniqueId,
                                   installedVersion: version, declaredKeys: keys,
                                   metadataNexusId: meta, errors: errors,
                                   heldFacts: held)
    }

    /// Facts d'un fichier posé par l'app : page, identifiant de fichier,
    /// date de mise en ligne (secondes Unix, comme `uploaded_timestamp`).
    private func facts(_ modId: String, fileId: Int, ts: Int) -> NexusInstallFacts {
        NexusInstallFacts(modId: modId, fileId: fileId,
                          fileUploadedAt: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// Un fichier publié par la page, tel que `files.json` le rend.
    private func pageFile(_ fileId: Int, ts: Int, label: String) -> NexusModFile {
        NexusModFile(fileId: fileId, categoryId: 1, categoryName: "MAIN",
                     version: label, modVersion: nil, uploadedTimestamp: ts)
    }

    // MARK: - Qui mérite une reprise

    @Test func laPageEstReprisQuandNexusLuiMemeAEchoue() {
        // Le cas fondateur : luisMint.PoweredAutomation, Nexus:50165.
        let plan = NexusFallbackCheck.plan([
            blocked("luisMint.PoweredAutomation", keys: ["Nexus:50165"],
                    errors: ["The Nexus mod with ID '50165' has no valid versions."])
        ])
        #expect(plan.count == 1)
        #expect(plan.first?.nexusId == "50165")
    }

    @Test func uneErreurSurUnAutreSiteNEstPasUneRaisonDeRejouerNexus() {
        // 18 mods du parc sont dans ce cas : leur clé Nexus a été consultée
        // avec succès, seule celle de CurseForge a échoué. Les reprendre
        // rejouerait un verdict déjà rendu, pour 18 requêtes.
        let plan = NexusFallbackCheck.plan([
            blocked("aedenthorn.AllChestsMenu", version: "0.4.2",
                    keys: ["Nexus:14494", "CurseForge:868705"], meta: 14494,
                    errors: ["The CurseForge mod with ID '868705' has no valid versions."]),
            blocked("Achtuur.StardewTravelSkill", version: "1.4.0",
                    keys: ["Nexus:16820", "GitHub:Achtuur/StardewTravelSkill"], meta: 16820,
                    errors: ["Found no GitHub release for this ID."])
        ])
        #expect(plan.isEmpty)
    }

    @Test func unModSansCleNexusEstReprisSurLIdentifiantQueSmapiConnait() {
        // 20 mods du parc n'ont d'identifiant que par `metadata.nexusID` —
        // dont Stardew Valley Expanded, **actif**, dont la clé vaut « ??? ».
        // smapi.io n'a donc jamais regardé Nexus pour eux.
        let plan = NexusFallbackCheck.plan([
            blocked("FlashShifter.SVECode", version: "1.15.11",
                    keys: ["Nexus:???"], meta: 3753,
                    errors: ["The value '???' isn't a valid Nexus mod ID, must be an integer ID."]),
            blocked("Airyn.KentGetsTherapy", version: "1.2.2",
                    keys: ["ModDrop:99999"], meta: 14535,
                    errors: ["Found no ModDrop mod with this ID."])
        ])
        #expect(plan.map(\.nexusId) == ["14535", "3753"])
    }

    @Test func sansAucunIdentifiantIlNYARienAInterroger() {
        // 51 mods du parc : ni clé exploitable, ni identifiant chez smapi.io.
        let plan = NexusFallbackCheck.plan([
            blocked("Aelinore.FievelPortrait", keys: ["Nexus:00000"],
                    errors: ["The value 'Nexus:00000' isn't a valid Nexus mod ID, must be an integer ID."]),
            blocked("nugmods.nyapuripley", keys: ["Nexus:null"],
                    errors: ["The value 'null' isn't a valid Nexus mod ID, must be an integer ID."]),
            blocked("yourdorkbrainsuhm", keys: ["Nexus:"],
                    errors: ["The update key 'Nexus:' isn't in a valid format."]),
            blocked("moonslime.ManaBarApi.CP", keys: ["-1"],
                    errors: ["The update key '-1' isn't in a valid format."])
        ])
        #expect(plan.isEmpty)
    }

    @Test func leManifesteLEmporteQuandSmapiNeLeContreditPas() {
        // Même règle que `NexusIdLearning` : le manifeste est ce que SMAPI lit.
        // smapi.io muette, ou d'accord, ne change rien.
        let muet = NexusFallbackCheck.plan([
            blocked("a.b", keys: ["Nexus:47216"], meta: nil,
                    errors: ["Found no Nexus mod with this ID."])
        ])
        #expect(muet.first?.nexusId == "47216")
        let accord = NexusFallbackCheck.plan([
            blocked("a.b", keys: ["Nexus:47216"], meta: 47216,
                    errors: ["Found no Nexus mod with this ID."])
        ])
        #expect(accord.first?.nexusId == "47216")
    }

    @Test func uneCleDementieParSmapiCedeLaPlace() {
        // *Automate* déclare `Nexus:50165` — la page de *Powered Automation*,
        // une clé copiée par erreur — et smapi.io le connaît sous 1063 en
        // rendant sa version. La clé déclarée vient d'échouer ; l'autre non.
        //
        // Sans cette règle les deux mods revendiquaient 50165 avec des
        // versions différentes, et la règle d'ambiguïté les écartait tous les
        // deux — la preuve fondatrice de B2-T10 comprise. C'est le défaut
        // relevé à sa première passe réelle, le 2026-08-27.
        let plan = NexusFallbackCheck.plan([
            blocked("Pathoschild.Automate", version: "2.6.1", keys: ["Nexus:50165"],
                    meta: 1063,
                    errors: ["The Nexus mod with ID '50165' has no valid versions."]),
            blocked("luisMint.PoweredAutomation", version: "1.0.0", keys: ["Nexus:50165"],
                    meta: nil,
                    errors: ["The Nexus mod with ID '50165' has no valid versions."])
        ])
        #expect(plan.map(\.nexusId) == ["1063", "50165"])
        #expect(plan.first(where: { $0.nexusId == "50165" })?.mods.map(\.uniqueId)
                == ["luisMint.PoweredAutomation"])
    }

    @Test func laVarianteApresArrobaseDesigneLaMemePage() {
        // SMAPI tolère `Nexus:1234@variante` ; la page reste la 1234.
        let plan = NexusFallbackCheck.plan([
            blocked("a.b", keys: ["Nexus:47216@Cinder"],
                    errors: ["Found no Nexus mod with this ID."])
        ])
        #expect(plan.first?.nexusId == "47216")
    }

    // MARK: - Une page, plusieurs mods

    @Test func lesComposantsDUnPackNeFontQuUneRequete() {
        // Les sept composants des Forgotten Caverns déclarent tous Nexus:47216
        // et la même version : une requête suffit à les juger tous. 53 mods du
        // parc se ramènent ainsi à 41 pages.
        let composants = ["Azathii.TheForgottenCaverns",
                          "Azathii.TheForgottenCaverns.FTM",
                          "Azathii.TheForgottenCaverns.FTM.Cinder",
                          "Azathii.TheForgottenCaverns.dll"]
            .map { blocked($0, version: "1.0.10", keys: ["Nexus:47216"],
                           errors: ["Found no Nexus mod with this ID."]) }
        let plan = NexusFallbackCheck.plan(composants)
        #expect(plan.count == 1)
        #expect(plan.first?.mods.count == 4)
    }

    @Test func unePageRevendiqueeParDesVersionsDifferentesNeJugePersonne() {
        // Nexus:38134 est déclaré par Pretty Anime Portraits (10.0.0) et Pretty
        // Anime Genderbends (7.0.0). smapi.io ne connaît **ni l'un ni l'autre**
        // (`metadata.id` vide des deux côtés) : rien ne dit lequel revendique la
        // page à raison, et une seule version de page ne peut pas les juger
        // tous les deux. Dernier filet — le cas 50165, lui, se résout en amont.
        let plan = NexusFallbackCheck.plan([
            blocked("dakota.prettyanimeportraits", version: "10.0.0", keys: ["Nexus:38134"],
                    errors: ["The Nexus mod with ID '38134' has no valid versions."]),
            blocked("dakota.prettyanimegenderbents", version: "7.0.0", keys: ["Nexus:38134"],
                    errors: ["The Nexus mod with ID '38134' has no valid versions."])
        ])
        #expect(plan.isEmpty)
    }

    @Test func lesModulesDUnMemeEnsembleRestentJugeables() {
        // Les quatre modules de Starblue UI vivent dans quatre dossiers
        // distincts mais partagent page et version : aucune ambiguïté.
        let plan = NexusFallbackCheck.plan(
            ["DylanJames.StarblueUIDeluxeJournal", "DylanJames.StarblueUILoveOfCooking",
             "DylanJames.StarblueUISpacecore", "DylanJames.StarblueUIUnlockableBundles"]
                .map { blocked($0, version: "0.0.1", keys: ["Nexus:31451"],
                               errors: ["Found no Nexus mod with this ID."]) })
        #expect(plan.count == 1)
        #expect(plan.first?.mods.count == 4)
    }

    // MARK: - Ce que la réponse permet d'affirmer

    private func target(_ mods: [NexusFallbackCheck.Blocked],
                        id: String = "50165") -> NexusFallbackCheck.Target {
        NexusFallbackCheck.Target(nexusId: id, mods: mods)
    }

    @Test func laPreuveFondatriceDonneBienUneLigne() {
        // Powered Automation : 1.0.0 posé, 1.025 publié. Les versions exotiques
        // du mod sont précisément ce que smapi.io refuse d'indexer.
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("luisMint.PoweredAutomation", version: "1.0.0",
                                 keys: ["Nexus:50165"], errors: ["x"])]),
            pageVersion: "1.025", uploadedTime: Date(timeIntervalSince1970: 1_755_000_000))
        #expect(rows.count == 1)
        #expect(rows.first?.latestVersion == "1.025")
        #expect(rows.first?.nexusModId == "50165")
        #expect(rows.first?.url == "https://www.nexusmods.com/stardewvalley/mods/50165")
        // À la différence de la voie smapi.io, qui la laisse toujours nulle.
        #expect(rows.first?.uploadedTime != nil)
    }

    @Test func unePageALaMemeVersionNeProduitRien() {
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("a.b", version: "1.0.10", errors: ["x"])], id: "47216"),
            pageVersion: "1.0.10", uploadedTime: nil)
        #expect(rows.isEmpty)
    }

    @Test func unePageSansVersionNAffirmeRien() {
        // L'API Nexus peut rendre une chaîne vide ; ce n'est pas un verdict.
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("a.b", version: "1.0.0", errors: ["x"])]),
            pageVersion: "   ", uploadedTime: nil)
        #expect(rows.isEmpty)
    }

    @Test func unCorrectifNonOfficielNEstPasRemplaceParLOfficiel() {
        // ZeroMeters.SAAT.Mod, parc réel : « 1.1.3-unofficial.1-p1xel8ted ».
        // Par la lettre du semver, 1.1.3 l'emporte — mais chez SMAPI cette
        // forme désigne un correctif **postérieur**. Proposer la page
        // conseillerait une régression.
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("ZeroMeters.SAAT.Mod",
                                 version: "1.1.3-unofficial.1-p1xel8ted", errors: ["x"])],
                        id: "10747"),
            pageVersion: "1.1.3", uploadedTime: nil)
        #expect(rows.isEmpty)
    }

    @Test func unCorrectifNonOfficielCedeQuandLaPageFranchitSonNumero() {
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("ZeroMeters.SAAT.Mod",
                                 version: "1.1.3-unofficial.1-p1xel8ted", errors: ["x"])],
                        id: "10747"),
            pageVersion: "1.2.0", uploadedTime: nil)
        #expect(rows.count == 1)
    }

    @Test func chaqueModDeLaPageRecoitSaPropreLigne() {
        let mods = ["Azathii.TheForgottenCaverns", "Azathii.TheForgottenCaverns.FTM"]
            .map { blocked($0, version: "1.0.10", errors: ["x"]) }
        let rows = NexusFallbackCheck.rows(for: target(mods, id: "47216"),
                                           pageVersion: "1.1.0", uploadedTime: nil)
        #expect(rows.map(\.uniqueId).sorted()
                == ["Azathii.TheForgottenCaverns", "Azathii.TheForgottenCaverns.FTM"])
        #expect(rows.allSatisfy { $0.installedVersion == "1.0.10" })
    }

    // MARK: - X9 : le fichier tenu, pas le libellé publié

    @Test func onTientLeMainLePlusRecentDoncPasDeLigne() {
        // ModCollectionAlbum (50802), constaté le 2026-08-31 : l'auteur a
        // monté les libellés 1→5 en deux jours, le manifeste de l'archive est
        // resté 1.2.0 — la ligne « vers 5 » renaissait après chaque
        // installation. On tient précisément le fichier que la page publie
        // encore comme MAIN le plus récent : aucune mise à jour n'existe.
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("Clmny.ModCollectionAlbum", version: "1.2.0",
                                 keys: ["Nexus:50802"], errors: ["x"],
                                 held: facts("50802", fileId: 5555, ts: 1_787_000_000))],
                        id: "50802"),
            pageVersion: "5",
            uploadedTime: Date(timeIntervalSince1970: 1_787_000_000),
            pageFile: pageFile(5555, ts: 1_787_000_000, label: "5"))
        #expect(rows.isEmpty)
    }

    @Test func unFichierRepubliePlusRecentDonneUneLigneMemeLibelle() {
        // La re-publication à numéro constant : aucun libellé ne bouge, mais
        // un nouveau fichier (nouvel id) est plus récent que celui qu'on
        // tient. C'est la « règle de re-publication du lot C », enfin
        // branchée — la comparaison de chaînes y est aveugle.
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("a.b", version: "1.2.0", errors: ["x"],
                                 held: facts("50165", fileId: 111, ts: 1_000))],
                        id: "50165"),
            pageVersion: "1.2.0", uploadedTime: nil,
            pageFile: pageFile(222, ts: 2_000, label: "1.2.0"))
        #expect(rows.count == 1)
        #expect(rows.first?.latestVersion == "1.2.0")
    }

    @Test func unFichierRetireParLAuteurNEstPasRemplaceParUnAncien() {
        // L'auteur supprime le fichier qu'on tient ; le MAIN le plus récent
        // de la page est un fichier plus **ancien**. Son libellé peut être
        // plus grand que le nôtre — proposer la page conseillerait un retour
        // arrière.
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("a.b", version: "1.2.0", errors: ["x"],
                                 held: facts("50165", fileId: 222, ts: 2_000))],
                        id: "50165"),
            pageVersion: "9", uploadedTime: nil,
            pageFile: pageFile(111, ts: 1_000, label: "9"))
        #expect(rows.isEmpty)
    }

    @Test func desFaitsDuneAutrePageNeDecidentPas() {
        // L'ancre décrit une autre page — l'identifiant Nexus du mod a changé
        // entre-temps, ou l'ancre survit à un déplacement. Elle ne dit rien
        // de celle-ci : la règle retombe sur les libellés, même si par
        // hasard les deux pages partagent un numéro de fichier.
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("a.b", version: "1.2.0", errors: ["x"],
                                 held: facts("99999", fileId: 111, ts: 1_000))],
                        id: "50165"),
            pageVersion: "5", uploadedTime: nil,
            pageFile: pageFile(111, ts: 1_000, label: "5"))
        #expect(rows.count == 1)
        #expect(rows.first?.latestVersion == "5")
    }

    @Test func sansListeDeFichiersLaRegleResteAuxLibelles() {
        // `files.json` illisible (réseau, quota) : on ne sait pas quel fichier
        // la page publie. Les faits qu'on tient ne peuvent pas trancher contre
        // le seul signal disponible, les libellés — on garde le verdict d'avant.
        let rows = NexusFallbackCheck.rows(
            for: target([blocked("a.b", version: "1.2.0", errors: ["x"],
                                 held: facts("50165", fileId: 111, ts: 1_000))],
                        id: "50165"),
            pageVersion: "5", uploadedTime: nil, pageFile: nil)
        #expect(rows.count == 1)
    }
}
