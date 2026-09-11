import Foundation
import Testing
@testable import StarHubTHCore

/// De quelle page Nexus vient ce qu'on dépose — et ce qu'on remplace en le
/// déposant.
///
/// Cette identité se lisait au milieu de `depositIntoMod` (ViewModel), en
/// quatre lignes de `??` chaînés commentées sur trente, et rien ne la
/// vérifiait. Ce qu'elle décide n'est pas cosmétique : sans identifiant, la
/// fiche affiche « aucune vérification de mise à jour » et attend un
/// rattachement à la main.
struct DepositIdentityTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let published = Date(timeIntervalSince1970: 1_600_000_000)

    private func hit(modId: Int, name: String = "Traduction FR",
                     version: String = "1.2.0", updatedAt: Date?) -> NexusModSearch.Hit {
        NexusModSearch.Hit(modId: modId, name: name, version: version, updatedAt: updatedAt,
                           categoryName: "Translations", uploader: "someone", adultContent: false)
    }

    // MARK: - D'où vient ce dépôt

    @Test func aNexusHitWinsOverEverythingElse() {
        let resolved = DepositIdentity.resolve(nexus: hit(modId: 42, updatedAt: published),
                                               sourceName: "MakeGuntherRealFR-34339-1-0-1748539543.zip",
                                               downloadedModId: 7, at: now)
        #expect(resolved.modId == 42)
        #expect(resolved.version == "1.2.0")
        #expect(resolved.updatedAt == published)
    }

    @Test func theFileNameIsReadWhenNoHitCameWithTheDeposit() {
        // Sur un compte gratuit tout s'installe à la main : le nom du fichier
        // téléchargé est la seule provenance disponible, et il la porte six
        // fois sur dix sur le parc réel.
        let resolved = DepositIdentity.resolve(nexus: nil,
                                               sourceName: "MakeGuntherRealFR-34339-1-0-1748539543.zip",
                                               downloadedModId: nil, at: now)
        #expect(resolved.modId == 34339)
        #expect(resolved.version == "1.0")
    }

    @Test func aDownloadedModIdIsUsedWhenTheNameSaysNothing() {
        // Le navigateur intégré sait de quelle page l'archive vient, même
        // quand le nom du fichier ne le dit pas.
        let resolved = DepositIdentity.resolve(nexus: nil, sourceName: "traduction.zip",
                                               downloadedModId: 7, at: now)
        #expect(resolved.modId == 7)
    }

    @Test func theFileNameIsPreferredToTheDownloadIdWhenBothSpeak() {
        let resolved = DepositIdentity.resolve(nexus: nil,
                                               sourceName: "MakeGuntherRealFR-34339-1-0-1748539543.zip",
                                               downloadedModId: 7, at: now)
        #expect(resolved.modId == 34339)
    }

    @Test func aDepositNobodyCanIdentifyCarriesNoIdAndNoDate() {
        // Sans identifiant, aucune date : `isNewer` ne doit pas pouvoir
        // conclure « à jour » sur une ligne dont on ignore la provenance.
        let resolved = DepositIdentity.resolve(nexus: nil, sourceName: "traduction.zip",
                                               downloadedModId: nil, at: now)
        #expect(resolved.modId == 0)
        #expect(resolved.version.isEmpty)
        #expect(resolved.updatedAt == nil)
    }

    // MARK: - La date retenue

    @Test func anIdentifiedDepositIsDatedFromTheDepositItself() {
        // Jamais la date que porte le nom : on sait quand l'utilisateur l'a
        // posée, et tout ce que Nexus a publié depuis est plus récent. Sans
        // cette date, `isNewer` refuse de conclure et l'identifiant appris ne
        // servirait à rien.
        let resolved = DepositIdentity.resolve(nexus: nil,
                                               sourceName: "MakeGuntherRealFR-34339-1-0-1748539543.zip",
                                               downloadedModId: nil, at: now)
        #expect(resolved.updatedAt == now)
    }

    @Test func aNexusHitKeepsItsOwnPublicationDate() {
        let resolved = DepositIdentity.resolve(nexus: hit(modId: 42, updatedAt: published),
                                               sourceName: "x.zip", downloadedModId: nil, at: now)
        #expect(resolved.updatedAt == published)
    }

    @Test func aNexusHitWithoutADateFallsBackOnTheDeposit() {
        let resolved = DepositIdentity.resolve(nexus: hit(modId: 42, updatedAt: nil),
                                               sourceName: "x.zip", downloadedModId: nil, at: now)
        #expect(resolved.updatedAt == now)
    }

    // MARK: - La ligne de registre

    @Test func theProbeAndTheRecordedLineShareOneIdentity() {
        // Deux lectures du même nom qui divergeraient donneraient une identité
        // au comparateur de doublon et une autre à ce qui est gardé.
        let resolved = DepositIdentity.resolve(nexus: nil,
                                               sourceName: "MakeGuntherRealFR-34339-1-0-1748539543.zip",
                                               downloadedModId: nil, at: now)
        let probe = resolved.entry(hostFolderName: "SVE", sourceName: "MakeGuntherRealFR-34339-1-0-1748539543.zip",
                                   installedAt: now, files: [], replacedFiles: [:])
        let recorded = resolved.entry(hostFolderName: "SVE", sourceName: "MakeGuntherRealFR-34339-1-0-1748539543.zip",
                                      installedAt: now, files: ["i18n/fr.json"],
                                      replacedFiles: [:])
        #expect(probe.nexusModId == recorded.nexusModId)
        #expect(probe.version == recorded.version)
        #expect(probe.updatedAt == recorded.updatedAt)
        #expect(recorded.files == ["i18n/fr.json"])
    }

    // MARK: - Ce qu'on remplace

    @Test func aTranslationReplacesTheTranslationOfTheSameMod() {
        var registry = InstalledTranslationRegistry()
        let previous = InstalledTranslation(hostFolderName: "SVE", nexusModId: 1,
                                            nexusName: "Ancienne", version: "1.0",
                                            updatedAt: nil, installedAt: now,
                                            files: [], replacedFiles: [:])
        registry.record(previous)
        let resolved = DepositIdentity.resolve(nexus: nil, sourceName: "neuve.zip",
                                               downloadedModId: nil, at: now)
        let probe = resolved.entry(hostFolderName: "SVE", sourceName: "neuve.zip",
                                   installedAt: now, files: [], replacedFiles: [:])

        #expect(DepositIdentity.incumbent(in: registry, kind: .translation,
                                          host: "SVE", probe: probe) == previous)
    }

    @Test func anAddonOnlyReplacesTheAddonOfTheSameIdentity() {
        // Une greffe n'écarte pas la traduction du même mod — elles ne
        // déposent pas les mêmes fichiers — mais elle écarte la greffe de même
        // identité, sans quoi redéposer un lot laisserait derrière lui les
        // fichiers de l'ancienne version.
        var registry = InstalledTranslationRegistry()
        let sameLot = InstalledTranslation(hostFolderName: "SVE", nexusModId: 34339,
                                           nexusName: "Sacs-34339-1-0-1748539543.zip", version: "1.0",
                                           updatedAt: nil, installedAt: now,
                                           files: ["assets/a.png"], replacedFiles: [:])
        let otherLot = InstalledTranslation(hostFolderName: "SVE", nexusModId: 55,
                                            nexusName: "Autre chose", version: "1.0",
                                            updatedAt: nil, installedAt: now,
                                            files: [], replacedFiles: [:])
        registry.recordAddon(otherLot)
        registry.recordAddon(sameLot)
        let resolved = DepositIdentity.resolve(nexus: nil, sourceName: "Sacs-34339-2-0-1758539543.zip",
                                               downloadedModId: nil, at: now)
        let probe = resolved.entry(hostFolderName: "SVE", sourceName: "Sacs-34339-2-0-1758539543.zip",
                                   installedAt: now, files: [], replacedFiles: [:])

        #expect(DepositIdentity.incumbent(in: registry, kind: .addon,
                                          host: "SVE", probe: probe) == sameLot)
    }

    @Test func anAddonDoesNotEvictTheTranslationOfTheSameMod() {
        var registry = InstalledTranslationRegistry()
        registry.record(InstalledTranslation(hostFolderName: "SVE", nexusModId: 1,
                                             nexusName: "Traduction", version: "1.0",
                                             updatedAt: nil, installedAt: now,
                                             files: [], replacedFiles: [:]))
        let resolved = DepositIdentity.resolve(nexus: nil, sourceName: "Sacs.zip",
                                               downloadedModId: nil, at: now)
        let probe = resolved.entry(hostFolderName: "SVE", sourceName: "Sacs.zip",
                                   installedAt: now, files: [], replacedFiles: [:])

        #expect(DepositIdentity.incumbent(in: registry, kind: .addon,
                                          host: "SVE", probe: probe) == nil)
    }

    @Test func nothingInPlaceMeansNothingToReplace() {
        let registry = InstalledTranslationRegistry()
        let resolved = DepositIdentity.resolve(nexus: nil, sourceName: "x.zip",
                                               downloadedModId: nil, at: now)
        let probe = resolved.entry(hostFolderName: "SVE", sourceName: "x.zip",
                                   installedAt: now, files: [], replacedFiles: [:])

        #expect(DepositIdentity.incumbent(in: registry, kind: .translation,
                                          host: "SVE", probe: probe) == nil)
    }
}
