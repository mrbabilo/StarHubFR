import Testing
import Foundation
@testable import StarHubTHCore

/// Les quatre formes viennent d'archives réelles, téléchargées depuis Nexus.
struct ManifestlessArchiveTests {
    private let parc = ["FishingLogbook", "The Queen of Sauce's Cookbook - Recipe Tracker",
                        "ItemBags", "[CP] Make Gunther Real", "Parchment",
                        "[CP] Parchment Example Pack"]

    // MARK: - Forme 1 : la destination est écrite dans l'archive

    @Test func aTranslationNamingItsHostIsPlannedOutright() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["FishingLogbook/i18n/fr.json"], installedFolderNames: parc)
        guard case .plan(let plan) = outcome else { Issue.record("attendu un plan"); return }
        #expect(plan.hostFolderName == "FishingLogbook")
        #expect(plan.kind == .translation)
        #expect(plan.entries == [.init(source: "FishingLogbook/i18n/fr.json",
                                       destination: "i18n/fr.json")])
    }

    /// Le mod hôte est **en pause** sur le parc réel : la classification rend
    /// son nom logique, à charge de l'appelant d'en tirer le nom physique. Le
    /// dossier pointé n'a rien à faire ici.
    @Test func aPausedHostIsNamedLogically() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["The Queen of Sauce's Cookbook - Recipe Tracker/i18n/fr.json"],
            installedFolderNames: parc)
        guard case .plan(let plan) = outcome else { Issue.record("attendu un plan"); return }
        #expect(plan.hostFolderName == "The Queen of Sauce's Cookbook - Recipe Tracker")
    }

    // MARK: - Forme 3 : greffe au chemin complet

    @Test func anAddonNamingItsHostKeepsItsWholePath() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["ItemBags/assets/Modded Bags/Cornucopia All Crops.json"],
            installedFolderNames: parc)
        guard case .plan(let plan) = outcome else { Issue.record("attendu un plan"); return }
        #expect(plan.hostFolderName == "ItemBags")
        #expect(plan.kind == .addon)
        #expect(plan.entries.first?.destination == "assets/Modded Bags/Cornucopia All Crops.json")
    }

    /// Un fichier hors du `i18n/` fait de l'archive une greffe, pas une
    /// traduction — même si elle porte aussi des fichiers de langue.
    @Test func aMixedArchiveIsAnAddon() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["ItemBags/i18n/fr.json", "ItemBags/assets/x.png"], installedFolderNames: parc)
        guard case .plan(let plan) = outcome else { Issue.record("attendu un plan"); return }
        #expect(plan.kind == .addon)
    }

    // MARK: - Forme 2 : le nom ne désigne aucun mod installé

    /// **Le cas qu'il ne faut surtout pas deviner.** Sur le parc réel,
    /// `MakeGuntherRealFR` vise un mod qui s'appelle `[CP] Make Gunther Real` :
    /// ni l'égalité ni le retrait d'un suffixe de langue n'y mènent. On demande.
    @Test func anUnmatchedFolderAsksRatherThanGuesses() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["MakeGuntherRealFR/dialogue.json"], installedFolderNames: parc)
        guard case .needsHost(let candidates, let kind, let entries) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        #expect(kind == .addon)
        #expect(entries.first?.destination == "dialogue.json")
        #expect(candidates.contains("[CP] Make Gunther Real"))
    }

    /// Le plus proche en longueur d'abord : pour un « ParchmentFR », le mod
    /// `Parchment` passe devant `[CP] Parchment Example Pack`.
    @Test func candidatesComeClosestFirst() {
        let found = ManifestlessArchive.candidates(for: "ParchmentFR", among: parc)
        #expect(found.first == "Parchment")
        #expect(found.contains("[CP] Parchment Example Pack"))
    }

    /// **Par mots communs, pas par sous-chaîne.** `MakeGuntherRealFR` et
    /// `[CP] Make Gunther Real` ne se contiennent pas l'un l'autre — le premier
    /// porte un suffixe, le second un préfixe. Il leur reste trois mots.
    @Test func matchingWorksOnWordsNotSubstrings() {
        #expect(ManifestlessArchive.significantWords("MakeGuntherRealFR")
                == ["make", "gunther", "real"])
        #expect(ManifestlessArchive.significantWords("[CP] Make Gunther Réal")
                == ["make", "gunther", "real"])
    }

    /// Marqueurs de langue et préfixes de convention n'identifient rien : le
    /// `FR` désigne la traduction, `[CP]` désigne Content Patcher.
    @Test func languageMarkersAndConventionPrefixesAreIgnored() {
        #expect(!ManifestlessArchive.significantWords("ModFR").contains("fr"))
        #expect(!ManifestlessArchive.significantWords("[CP] Truc").contains("cp"))
    }

    /// Un nom qui ne serait fait que de bruit ne propose rien plutôt que tout.
    @Test func aNameMadeOnlyOfNoiseProposesNothing() {
        #expect(ManifestlessArchive.candidates(for: "[CP] FR", among: parc).isEmpty)
    }

    @Test func nothingResemblingItLeavesTheListEmpty() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["ZzzUnknownMod/x.json"], installedFolderNames: parc)
        guard case .needsHost(let candidates, _, _) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        #expect(candidates.isEmpty)
    }

    // MARK: - Forme 5 : un dossier de présentation en emballe un autre

    /// Archive réelle : `Nyapu Style Lilybrook/[CP] Lilybrook/Assets/…`. La
    /// racine ne désigne rien ; le niveau en dessous vise le mod installé.
    /// Sans la descente, l'archive partait en « à désigner » avec des candidats
    /// tirés du mauvais nom.
    @Test func aWrapperFolderIsSteppedThrough() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["Nyapu Style Lilybrook/[CP] Lilybrook/Assets/Portraits/Anya.png"],
            installedFolderNames: ["Lilybrook", "Parchment"])
        guard case .needsHost(let candidates, _, let entries) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        // Les chemins sont relatifs au dossier **intérieur**, pas à l'emballage.
        #expect(entries.first?.destination == "Assets/Portraits/Anya.png")
        #expect(candidates.first == "Lilybrook")
    }

    /// Quand le dossier intérieur porte exactement le nom d'un mod installé,
    /// la descente donne un plan et non une question.
    @Test func aWrapperAroundAKnownModIsPlannedOutright() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["Pack de portraits/Parchment/assets/x.png"],
            installedFolderNames: ["Parchment"])
        guard case .plan(let plan) = outcome else { Issue.record("attendu un plan"); return }
        #expect(plan.hostFolderName == "Parchment")
        #expect(plan.entries.first?.destination == "assets/x.png")
    }

    /// On ne descend pas quand la racine désigne déjà un mod : `ItemBags/assets/…`
    /// ne doit pas devenir « assets », qui n'est le nom de rien.
    @Test func aRecognisedRootIsNotSteppedThrough() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["ItemBags/assets/Modded Bags/x.json"], installedFolderNames: parc)
        guard case .plan(let plan) = outcome else { Issue.record("attendu un plan"); return }
        #expect(plan.hostFolderName == "ItemBags")
        #expect(plan.entries.first?.destination == "assets/Modded Bags/x.json")
    }

    /// On ne descend pas non plus quand le niveau du dessous n'évoque rien :
    /// mieux vaut demander sur le nom de la racine, qui a au moins un sens.
    @Test func aWrapperAroundNothingKnownStaysOnItsRoot() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["MakeGuntherRealFR/zzz/x.json"], installedFolderNames: parc)
        guard case .needsHost(let candidates, _, let entries) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        #expect(candidates.first == "[CP] Make Gunther Real")
        #expect(entries.first?.destination == "zzz/x.json")
    }

    // MARK: - Forme 4 : des chemins déjà relatifs à la racine du mod

    /// **Le décapage de trop.** `i18n` n'est pas le nom d'un mod : le retirer
    /// poserait le `fr.json` à la racine du dossier, où le jeu ne le lira
    /// jamais — et la fiche annoncerait pourtant une traduction en place.
    @Test func anArchiveRootedOnI18nKeepsItsFolder() throws {
        let outcome = ManifestlessArchive.classify(paths: ["i18n/fr.json"],
                                                   installedFolderNames: parc)
        guard case .needsHost(let candidates, let kind, let entries) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        #expect(candidates.isEmpty)
        #expect(kind == .translation)
        #expect(entries.map(\.destination) == ["i18n/fr.json"])
    }

    /// Plusieurs dossiers de contenu à la tête : l'archive reste relative à la
    /// racine du mod, elle n'a pas « plusieurs racines » au sens du refus.
    @Test func severalContentFoldersStayRootRelative() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["i18n/fr.json", "assets/portrait.png"], installedFolderNames: parc)
        guard case .needsHost(_, let kind, let entries) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        // Un seul fichier hors `i18n/` suffit : ce n'est plus une traduction
        // pure, et le registre des traductions ne doit pas s'en emparer.
        #expect(kind == .addon)
        #expect(entries.map(\.destination) == ["i18n/fr.json", "assets/portrait.png"])
    }

    /// Un mod réellement nommé comme un dossier de contenu garde la main : son
    /// nom écrit dans l'archive dit où déposer.
    @Test func anInstalledModNamedLikeAContentFolderWins() throws {
        let outcome = ManifestlessArchive.classify(paths: ["assets/data.json"],
                                                   installedFolderNames: ["assets"])
        guard case .plan(let plan) = outcome else { Issue.record("attendu un plan"); return }
        #expect(plan.hostFolderName == "assets")
        #expect(plan.entries.map(\.destination) == ["data.json"])
    }

    /// `Content/` est le dossier du **jeu** : une archive qui en porte un n'est
    /// pas relative à la racine d'un mod, et l'y déposer serait un contresens.
    @Test func aContentRootedArchiveIsNotTakenAsModRelative() throws {
        let outcome = ManifestlessArchive.classify(paths: ["Content/Maps/x.xnb"],
                                                   installedFolderNames: parc)
        guard case .needsHost(_, _, let entries) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        #expect(entries.map(\.destination) == ["Maps/x.xnb"])
    }

    /// Des fichiers nus que rien ne situe : refusés. Déposer au hasard dans un
    /// mod est pire que ne rien faire.
    @Test func bareFilesThatNothingIdentifiesAreRefused() {
        #expect(ManifestlessArchive.classify(paths: ["notes.txt", "readme.md"],
                                             installedFolderNames: parc) == .unrecognised)
    }

    // MARK: - Refus

    @Test func anEmptyArchiveIsRefused() {
        #expect(ManifestlessArchive.classify(paths: [], installedFolderNames: parc) == .unrecognised)
        #expect(ManifestlessArchive.classify(paths: ["Dossier/"], installedFolderNames: parc)
                == .unrecognised)
    }

    /// Deux dossiers racine, ou un fichier posé à côté d'un dossier : l'archive
    /// ne dit pas où elle va.
    @Test func severalRootsAreRefused() {
        #expect(ManifestlessArchive.classify(paths: ["A/x.json", "B/y.json"],
                                             installedFolderNames: parc) == .unrecognised)
        #expect(ManifestlessArchive.classify(paths: ["A/x.json", "lisezmoi.txt"],
                                             installedFolderNames: parc) == .unrecognised)
    }

    /// Un dossier vide de tout fichier utile ne donne pas de plan.
    @Test func aRootWithNothingUnderItIsRefused() {
        #expect(ManifestlessArchive.classify(paths: ["FishingLogbook/"],
                                             installedFolderNames: parc) == .unrecognised)
    }

    // MARK: - Forme 5 : un fichier nu qui remplace un fichier déjà là

    /// **Le cas réel qui a fait naître cette forme.** `bagconfig.json`, seul
    /// dans son archive, est un remplacement de configuration pour `ItemBags` —
    /// un genre entier sur Nexus. Les deux reconnaisseurs le refusaient : il
    /// n'a pas de dossier, et ses clés ne sont pas celles d'un sac.
    @Test func aBareConfigFileGoesToTheModThatAlreadyHasOne() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["bagconfig.json"], installedFolderNames: parc,
            rootFileOwners: ["bagconfig.json": ["ItemBags"]])
        guard case .plan(let plan) = outcome else { Issue.record("attendu un plan"); return }
        #expect(plan.hostFolderName == "ItemBags")
        #expect(plan.entries.map(\.destination) == ["bagconfig.json"])
    }

    /// **Là où il faut s'abstenir.** `config.json` est porté par 544 mods du
    /// parc, `content.json` par 522 : deviner écrirait dans le mauvais dossier.
    @Test func aFileNameCarriedByManyModsAsksInstead() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["config.json"], installedFolderNames: parc,
            rootFileOwners: ["config.json": ["Parchment", "ItemBags", "Automate"]])
        guard case .needsHost(let candidates, _, _) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        #expect(candidates == ["Automate", "ItemBags", "Parchment"])
    }

    /// Un nom qu'aucun mod ne porte ne conclut rien : c'est le cas des
    /// définitions de sacs, que leur contenu situe ailleurs.
    @Test func anUnknownBareFileNameConcludesNothing() {
        #expect(ManifestlessArchive.classify(
            paths: ["Cloth and Colors Bag.json"], installedFolderNames: parc,
            rootFileOwners: ["bagconfig.json": ["ItemBags"]]) == .unrecognised)
    }

    /// **Un `manifest.json` nu n'est jamais un remplacement.** 989 mods en
    /// portent un ; le reconnaître ferait proposer d'écraser le manifeste d'un
    /// mod au hasard.
    @Test func aBareManifestIsNeverAReplacement() {
        #expect(ManifestlessArchive.classify(
            paths: ["manifest.json"], installedFolderNames: parc,
            rootFileOwners: ["manifest.json": ["Parchment"]]) == .unrecognised)
    }

    /// Deux fichiers qui viseraient deux mods différents : on demande plutôt
    /// que d'en écraser un au hasard.
    @Test func filesAimingAtDifferentModsAskFirst() throws {
        let outcome = ManifestlessArchive.classify(
            paths: ["bagconfig.json", "other.json"], installedFolderNames: parc,
            rootFileOwners: ["bagconfig.json": ["ItemBags"], "other.json": ["Parchment"]])
        guard case .needsHost(let candidates, _, _) = outcome else {
            Issue.record("attendu une demande d'hôte"); return
        }
        #expect(candidates == ["ItemBags", "Parchment"])
    }

    /// Sans index des fichiers du parc, la forme ne se déclenche pas : les
    /// appelants qui ne le fournissent pas gardent le comportement d'avant.
    @Test func withoutTheIndexNothingChanges() {
        #expect(ManifestlessArchive.classify(paths: ["bagconfig.json"],
                                             installedFolderNames: parc) == .unrecognised)
    }
}
