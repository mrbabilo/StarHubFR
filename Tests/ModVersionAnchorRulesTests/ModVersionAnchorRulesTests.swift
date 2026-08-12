import Testing
import Foundation
@testable import StarHubTHCore

/// Ces règles décident quand l'app a le droit d'affirmer une version. Chacune
/// verrouille une manière précise de se tromper, toutes rencontrées :
/// affirmer sans constat, éteindre une ligne à chaque rescan, ou perdre les
/// faits Nexus d'une installation en les écrasant.
struct ModVersionAnchorRulesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let before = Date(timeIntervalSince1970: 1_700_000_000)

    private func facts(_ modId: String = "22256", file: Int = 1) -> NexusInstallFacts {
        NexusInstallFacts(modId: modId, fileId: file, fileUploadedAt: before)
    }

    // MARK: installation

    @Test func installingTheReferenceFileAnchorsTheVersion() {
        let anchor = ModVersionAnchorRules.afterInstall(
            existing: nil, uniqueId: "a", installedVersion: "1.18.0",
            facts: facts(), isReferenceFile: true, now: now)
        #expect(anchor?.anchoredVersion == "1.18.0")
        #expect(anchor?.origin == .install)
        #expect(anchor?.nexusFacts?.fileId == 1)
    }

    @Test func installingASecondaryFileKeepsTheVersionUntouched() {
        // Poser un optionnel de Swim Mod ne dit rien de la version du fichier
        // principal. Affirmer 1.0.2 ici éteindrait la mise à jour du cœur.
        let existing = ModVersionAnchor(uniqueId: "a", anchoredVersion: "1.9.0",
                                        origin: .install, anchoredAt: before,
                                        nexusFacts: facts(file: 7))
        let anchor = ModVersionAnchorRules.afterInstall(
            existing: existing, uniqueId: "a", installedVersion: "1.0.2",
            facts: facts(file: 9), isReferenceFile: false, now: now)
        #expect(anchor?.anchoredVersion == "1.9.0")
        #expect(anchor?.nexusFacts?.fileId == 9, "les faits du fichier posé sont enregistrés")
    }

    @Test func installingASecondaryFileWithNoPriorAnchorAnchorsNothing() {
        // Sans ancre préalable, on n'a aucune version à conserver : il ne faut
        // surtout pas affirmer celle de l'optionnel.
        let anchor = ModVersionAnchorRules.afterInstall(
            existing: nil, uniqueId: "a", installedVersion: "1.0.2",
            facts: facts(), isReferenceFile: false, now: now)
        #expect(anchor == nil)
    }

    @Test func installingWithoutNexusFactsAnchorsTheVersionAndStoresNoFacts() {
        // Le lot A ne va pas chercher `files.json` : il ignore le vrai
        // `file_id` et sa date. Inventer des valeurs ferait déclencher à tort
        // la règle de re-publication du lot C sur toute page mise à jour après
        // l'installation. `nil` dit « je ne sais pas ».
        let anchor = ModVersionAnchorRules.afterInstall(
            existing: nil, uniqueId: "a", installedVersion: "1.18.0",
            facts: nil, isReferenceFile: true, now: now)
        #expect(anchor?.anchoredVersion == "1.18.0")
        #expect(anchor?.origin == .install)
        #expect(anchor?.nexusFacts == nil)
    }

    @Test func installingWithoutFactsKeepsThoseAlreadyKnown() {
        // Une installation ultérieure sans faits ne doit pas effacer ceux
        // qu'une installation antérieure avait enregistrés.
        let existing = ModVersionAnchor(uniqueId: "a", anchoredVersion: "1.0.0",
                                        origin: .install, anchoredAt: before,
                                        nexusFacts: facts(file: 3))
        let anchor = ModVersionAnchorRules.afterInstall(
            existing: existing, uniqueId: "a", installedVersion: "2.0.0",
            facts: nil, isReferenceFile: true, now: now)
        #expect(anchor?.anchoredVersion == "2.0.0")
        #expect(anchor?.nexusFacts?.fileId == 3)
    }

    @Test func aReferenceReinstallWithNewFactsOverwritesTheOldOnes() {
        // Miroir du test précédent : une réinstallation du fichier principal
        // rafraîchit le `file_id` et la date de mise en ligne réellement posés.
        // Garder l'ancien fait ferait reposer la règle de re-publication (lot C)
        // sur un fichier périmé et manquer un correctif reposté sous le même
        // numéro. Le nouveau fait l'emporte, l'ancien ne s'intercale pas.
        let existing = ModVersionAnchor(uniqueId: "a", anchoredVersion: "1.0.0",
                                        origin: .install, anchoredAt: before,
                                        nexusFacts: facts(file: 3))
        let anchor = ModVersionAnchorRules.afterInstall(
            existing: existing, uniqueId: "a", installedVersion: "2.0.0",
            facts: facts(file: 10), isReferenceFile: true, now: now)
        #expect(anchor?.anchoredVersion == "2.0.0")
        #expect(anchor?.nexusFacts?.fileId == 10, "le nouveau fait Nexus l'emporte sur l'ancien")
    }

    // MARK: affirmation

    @Test func userAffirmationAnchorsTheSuggestedVersion() {
        let anchor = ModVersionAnchorRules.afterUserAffirmation(
            uniqueId: "a", version: "2.2.0", now: now)
        #expect(anchor.anchoredVersion == "2.2.0")
        #expect(anchor.origin == .userAffirmed)
        #expect(anchor.nexusFacts == nil)
    }

    // MARK: constat disque

    @Test func anUnchangedManifestVersionAnchorsNothing() {
        // LE défaut à ne pas reproduire. « le manifest a rejoint la version
        // cible » est vrai en permanence pour ~800 mods à jour : formulée
        // comme un état, la règle se déclencherait à chaque rescan et
        // éteindrait des lignes sans qu'on ait rien installé.
        let anchor = ModVersionAnchorRules.afterDiskChange(
            existing: nil, uniqueId: "a",
            previousManifestVersion: "2.0.4", currentManifestVersion: "2.0.4",
            suggestedVersion: "2.0.4", now: now)
        #expect(anchor == nil)
    }

    @Test func aManifestVersionThatChangedAndReachedTheTargetAnchors() {
        let anchor = ModVersionAnchorRules.afterDiskChange(
            existing: nil, uniqueId: "a",
            previousManifestVersion: "1.10.0", currentManifestVersion: "1.12.1",
            suggestedVersion: "1.12.1", now: now)
        #expect(anchor?.anchoredVersion == "1.12.1")
        #expect(anchor?.origin == .diskObserved)
    }

    @Test func aManifestVersionThatChangedWithoutReachingTheTargetAnchorsNothing() {
        // 1.10 → 1.11 alors que la cible est 1.12.1 : installation partielle,
        // la mise à jour reste due.
        let anchor = ModVersionAnchorRules.afterDiskChange(
            existing: nil, uniqueId: "a",
            previousManifestVersion: "1.10.0", currentManifestVersion: "1.11.0",
            suggestedVersion: "1.12.1", now: now)
        #expect(anchor == nil)
    }

    @Test func aManifestVersionOvershootingTheTargetAnchors() {
        // L'utilisateur a posé une préversion plus haute que ce que la source
        // annonce. Il a bien fait quelque chose : l'ancre suit.
        let anchor = ModVersionAnchorRules.afterDiskChange(
            existing: nil, uniqueId: "a",
            previousManifestVersion: "1.10.0", currentManifestVersion: "2.0.0",
            suggestedVersion: "1.12.1", now: now)
        #expect(anchor?.anchoredVersion == "2.0.0")
    }

    @Test func anInstallAnchorIsNeverDowngradedToDiskObserved() {
        // Dégrader jetterait `nexusFacts`, et avec eux la seule date qui
        // permette de voir une re-publication à version constante.
        let existing = ModVersionAnchor(uniqueId: "a", anchoredVersion: "1.12.1",
                                        origin: .install, anchoredAt: before,
                                        nexusFacts: facts())
        let anchor = ModVersionAnchorRules.afterDiskChange(
            existing: existing, uniqueId: "a",
            previousManifestVersion: "1.10.0", currentManifestVersion: "1.12.1",
            suggestedVersion: "1.12.1", now: now)
        #expect(anchor == nil, "l'ancre d'installation reste en place")
    }

    @Test func aDiskChangeBeyondAnInstallAnchorStillAnchors() {
        // L'utilisateur a posé 2.0.0 à la main par-dessus une installation
        // 1.12.1 faite par l'app : le disque a bougé au-delà, il faut suivre.
        let existing = ModVersionAnchor(uniqueId: "a", anchoredVersion: "1.12.1",
                                        origin: .install, anchoredAt: before,
                                        nexusFacts: facts())
        let anchor = ModVersionAnchorRules.afterDiskChange(
            existing: existing, uniqueId: "a",
            previousManifestVersion: "1.12.1", currentManifestVersion: "2.0.0",
            suggestedVersion: "2.0.0", now: now)
        #expect(anchor?.anchoredVersion == "2.0.0")
        #expect(anchor?.origin == .diskObserved)
        #expect(anchor?.nexusFacts?.modId == "22256", "les faits Nexus sont reportés")
    }

    @Test func aDiskChangeOverridesAUserAffirmedAnchor() {
        // Seules les ancres `.install` sont protégées, et c'est délibéré : elles
        // seules portent la date de fichier Nexus, irremplaçable. Une affirmation
        // n'a aucun fait à perdre, et le manifeste est ce que SMAPI charge — quand
        // il bouge, il est la vérité de terrain, même face au mot de
        // l'utilisateur. Une affirmation que le disque ne contredit jamais (pas
        // de changement) tient, elle : seul l'événement fait céder.
        let existing = ModVersionAnchor(uniqueId: "a", anchoredVersion: "2.0.0",
                                        origin: .userAffirmed, anchoredAt: before,
                                        nexusFacts: nil)
        let anchor = ModVersionAnchorRules.afterDiskChange(
            existing: existing, uniqueId: "a",
            previousManifestVersion: "1.0.0", currentManifestVersion: "1.5.0",
            suggestedVersion: "1.5.0", now: now)
        #expect(anchor?.anchoredVersion == "1.5.0")
        #expect(anchor?.origin == .diskObserved)
        #expect(anchor?.nexusFacts == nil, "une affirmation ne portait aucun fait à conserver")
    }
}
