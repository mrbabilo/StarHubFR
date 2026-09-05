import Testing
import Foundation
@testable import StarHubTHCore

/// La règle qui décide qu'un fichier de sauvegarde est « écrit par
/// l'utilisateur ». L'appariement des traductions se fait **sur les chemins
/// posés pour ce mod-là** : le registre est indexé par hôte, et un
/// `i18n/fr.json` d'auteur ne doit pas être reclamé parce qu'un *autre* mod
/// a sa traduction posée au même chemin relatif.
///
/// Mesuré sur le parc le 2026-09-05 : 59 fichiers étaient étiquetés
/// traduction par appariement tous-hôtes — tous des `i18n/*.json` d'auteur.
struct UserFileClassificationTests {

    @Test func configIsRecognizedByNameWithNoRegistryAtAll() {
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "config.json", hostTranslationPaths: []) == .config)
    }

    @Test func configRecognitionIgnoresCase() {
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "sub/Config.JSON", hostTranslationPaths: []) == .config)
    }

    @Test func ownHostTranslationMatchesBySuffix() {
        // Le chemin du registre porte l'hôte en tête, le chemin de sauvegarde
        // est relatif à la racine du mod : l'appariement se fait par suffixe.
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "i18n/fr.json",
            hostTranslationPaths: ["ModA/i18n/fr.json"]) == .translation)
    }

    /// Le cas parc de X75 : la sauvegarde est celle d'un mod **sans**
    /// traduction posée — l'ensemble qu'on lui passe est vide, quand bien
    /// même d'autres mods du parc ont leur `i18n/fr.json` à eux. C'est le
    /// bornage à l'hôte, fait par l'appelant, qui protège ; la règle de
    /// suffixe seule ne peut pas distinguer les hôtes — un chemin d'un autre
    /// hôte présent dans l'ensemble apparierait par suffixe.
    @Test func authorTranslationWithNoRegistryEntryForItsHostIsNotUserFile() {
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "i18n/fr.json", hostTranslationPaths: []) == nil)
    }

    @Test func packComponentTranslationMatchesItsRegistryPath() {
        // L'hôte est un composant de pack : son chemin de registre porte
        // `Pack/Composant` en tête, le fichier de sauvegarde est relatif au
        // composant.
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "i18n/fr.json",
            hostTranslationPaths: ["Pack/Composant/i18n/fr.json"]) == .translation)
    }

    @Test func registryPathAlreadyRelativeMatchesByEquality() {
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "i18n/fr.json",
            hostTranslationPaths: ["i18n/fr.json"]) == .translation)
    }

    @Test func matchingStopsAtASlashBoundary() {
        // Règle de segment préexistante, conservée : `fr.json` au bord d'un
        // slash du chemin de registre apparie, mais `r.json` n'apparie pas.
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "fr.json",
            hostTranslationPaths: ["ModA/i18n/fr.json"]) == .translation)
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "r.json",
            hostTranslationPaths: ["ModA/i18n/fr.json"]) == nil)
    }

    @Test func configWinsOverTranslationWhenBothApply() {
        // Ordre préexistant : le nom tranche avant le registre — un
        // `config.json` ne devient pas une traduction parce que le registre
        // le liste.
        #expect(MaintenanceInventory.classifyUserFile(
            relativePath: "config.json",
            hostTranslationPaths: ["ModA/config.json"]) == .config)
    }
}
