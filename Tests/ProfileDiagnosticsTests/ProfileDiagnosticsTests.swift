import Foundation
import Testing
@testable import StarHubTHCore

@Suite struct ProfileDiagnosticsTests {

    // MARK: - Ce qui manque

    /// Le cœur de B3-T4 : un profil peut réclamer un mod qui n'est plus
    /// installé. Mesuré sur le parc réel le 2026-08-24 — 10 et 6 sur deux de
    /// ses trois profils.
    @Test func aModTheProfileAsksForButIsNotInstalledIsMissing() {
        let profile = ModProfile(name: "Solo", enabledModIds: ["a.mod", "b.mod"])

        let missing = ProfileDiagnostics.missingMods(in: profile,
                                                     installedUniqueIds: ["a.mod"],
                                                     backupNames: [:],
                                                     nexusHints: [:])

        #expect(missing.map(\.uniqueId) == ["b.mod"])
    }

    /// L'ordre du profil est conservé : c'est celui dans lequel l'utilisateur
    /// a vu ses mods, et un tri alphabétique de plus n'apprendrait rien.
    @Test func missingModsKeepTheProfileOrder() {
        let profile = ModProfile(name: "Solo", enabledModIds: ["z.mod", "a.mod", "m.mod"])

        let missing = ProfileDiagnostics.missingMods(in: profile,
                                                     installedUniqueIds: [],
                                                     backupNames: [:],
                                                     nexusHints: [:])

        #expect(missing.map(\.uniqueId) == ["z.mod", "a.mod", "m.mod"])
    }

    /// SMAPI compare les identifiants sans tenir compte de la casse ; un
    /// manifeste réédité avec une majuscule différente ne doit pas faire
    /// passer un mod installé pour disparu.
    @Test func anIdThatDiffersOnlyByCaseIsNotMissing() {
        let profile = ModProfile(name: "Solo", enabledModIds: ["Author.MyMod"])

        let missing = ProfileDiagnostics.missingMods(in: profile,
                                                     installedUniqueIds: ["author.mymod"],
                                                     backupNames: [:],
                                                     nexusHints: [:])

        #expect(missing.isEmpty)
    }

    // MARK: - Ce qu'on sait dire du mod absent

    /// Le profil retient le nom depuis 2026-08-24. C'est la seule source qui
    /// couvre vraiment : un mod désinstallé n'est plus nulle part ailleurs.
    @Test func theProfilesOwnMetadataNamesTheMissingMod() {
        var profile = ModProfile(name: "Solo", enabledModIds: ["a.mod"])
        profile.modMetadata = ["a.mod": ProfileModMetadata(name: "A Mod", nexusModId: "1234")]

        let missing = ProfileDiagnostics.missingMods(in: profile,
                                                     installedUniqueIds: [],
                                                     backupNames: [:],
                                                     nexusHints: [:])

        #expect(missing.first?.name == "A Mod")
        #expect(missing.first?.nexusModId == "1234")
    }

    /// Pour les profils d'avant, il reste les sauvegardes : elles portent le
    /// nom du mod, faute de son identifiant Nexus.
    @Test func aBackupNamesAModTheProfileNeverRecorded() {
        let profile = ModProfile(name: "Solo", enabledModIds: ["a.mod"])

        let missing = ProfileDiagnostics.missingMods(in: profile,
                                                     installedUniqueIds: [],
                                                     backupNames: ["a.mod": "A Mod"],
                                                     nexusHints: [:])

        #expect(missing.first?.name == "A Mod")
        #expect(missing.first?.hasBackup == true)
    }

    /// Le cache des mises à jour Nexus donne les deux, quand le mod y figure.
    @Test func theNexusUpdateCacheCanSupplyBothNameAndModId() {
        let profile = ModProfile(name: "Solo", enabledModIds: ["asf"])

        let missing = ProfileDiagnostics.missingMods(
            in: profile,
            installedUniqueIds: [],
            backupNames: [:],
            nexusHints: ["asf": ProfileModMetadata(name: "Aquatic Sea Fish", nexusModId: "38752")])

        #expect(missing.first?.name == "Aquatic Sea Fish")
        #expect(missing.first?.nexusModId == "38752")
    }

    /// Ce que le profil a retenu prime : c'est ce qui était vrai au moment où
    /// le mod y est entré, quand les autres sources parlent d'un homonyme ou
    /// d'un état plus ancien.
    @Test func theProfilesMetadataWinsOverTheOtherSources() {
        var profile = ModProfile(name: "Solo", enabledModIds: ["a.mod"])
        profile.modMetadata = ["a.mod": ProfileModMetadata(name: "Le bon nom", nexusModId: "1")]

        let missing = ProfileDiagnostics.missingMods(
            in: profile,
            installedUniqueIds: [],
            backupNames: ["a.mod": "Un vieux nom"],
            nexusHints: ["a.mod": ProfileModMetadata(name: "Un autre", nexusModId: "2")])

        #expect(missing.first?.name == "Le bon nom")
        #expect(missing.first?.nexusModId == "1")
    }

    /// Sans aucune source, il reste l'identifiant — et il se lit mieux que
    /// `ThaleTheGreat.WalletToolsForTractorMod`.
    @Test func anUnknownModIsNamedFromItsIdentifier() {
        let profile = ModProfile(name: "Solo", enabledModIds: ["ThaleTheGreat.WalletToolsForTractorMod"])

        let missing = ProfileDiagnostics.missingMods(in: profile,
                                                     installedUniqueIds: [],
                                                     backupNames: [:],
                                                     nexusHints: [:])

        #expect(missing.first?.name == nil)
        #expect(missing.first?.displayName == "Wallet Tools For Tractor Mod")
    }

    @Test func anIdentifierWithoutAnAuthorPrefixIsLeftAlone() {
        #expect(ProfileDiagnostics.readableName(from: "ASF") == "ASF")
    }

    @Test func anIdentifierWithSeveralDotsKeepsOnlyItsLastSegment() {
        #expect(ProfileDiagnostics.readableName(from: "Azathii.TheForgottenCaverns.FTM") == "FTM")
    }

    /// Les mods livrés **avec** SMAPI ne se téléchargent pas sur Nexus : ils
    /// reviennent avec une réinstallation de SMAPI. Les présenter comme
    /// téléchargeables serait un mauvais conseil — les deux profils de
    /// référence en portent.
    @Test func smapiOwnModsAreFlaggedAsBundled() {
        let profile = ModProfile(name: "Solo", enabledModIds: ["SMAPI.SaveBackup", "other.mod"])

        let missing = ProfileDiagnostics.missingMods(in: profile,
                                                     installedUniqueIds: [],
                                                     backupNames: [:],
                                                     nexusHints: [:])

        #expect(missing.first?.isBundledWithSmapi == true)
        #expect(missing.last?.isBundledWithSmapi == false)
    }

    /// La pastille de la page des profils compte sans enrichissement (elle se
    /// rafraîchit à chaque rendu, l'enrichissement lit le disque) ; la feuille
    /// compte avec. Les deux nombres doivent rester égaux : l'enrichissement
    /// **décrit**, il ne filtre pas.
    @Test func enrichmentNeverChangesHowManyModsAreMissing() {
        var profile = ModProfile(name: "Solo", enabledModIds: ["a.mod", "b.mod", "SMAPI.SaveBackup"])
        profile.modMetadata = ["a.mod": ProfileModMetadata(name: "A Mod", nexusModId: "1")]

        let bare = ProfileDiagnostics.missingMods(in: profile,
                                                  installedUniqueIds: ["b.mod"],
                                                  backupNames: [:],
                                                  nexusHints: [:])
        let enriched = ProfileDiagnostics.missingMods(
            in: profile,
            installedUniqueIds: ["b.mod"],
            backupNames: ["a.mod": "A Mod", "smapi.savebackup": "Save Backup"],
            nexusHints: ["a.mod": ProfileModMetadata(name: "A", nexusModId: "9")])

        #expect(bare.map(\.uniqueId) == enriched.map(\.uniqueId))
    }

    // MARK: - Décodage des profils déjà enregistrés

    /// Ses trois profils sont écrits dans les préférences **sans** ce champ.
    /// Un décodage strict les ferait disparaître au prochain lancement.
    @Test func aProfileSavedBeforeTheMetadataFieldStillDecodes() throws {
        let legacy = """
        {"id":"6E1B2E4E-0000-0000-0000-000000000001","name":"OK","enabledModIds":["a.mod"]}
        """
        let profile = try JSONDecoder().decode(ModProfile.self, from: Data(legacy.utf8))

        #expect(profile.name == "OK")
        #expect(profile.enabledModIds == ["a.mod"])
        #expect(profile.modMetadata.isEmpty)
    }

    @Test func aProfileRoundTripsThroughItsStoredForm() throws {
        var profile = ModProfile(name: "Solo", enabledModIds: ["a.mod"])
        profile.modMetadata = ["a.mod": ProfileModMetadata(name: "A Mod", nexusModId: "7")]

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ModProfile.self, from: data)

        #expect(decoded == profile)
    }
}
