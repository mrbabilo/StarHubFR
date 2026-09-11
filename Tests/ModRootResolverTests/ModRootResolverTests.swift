import Foundation
import Testing
@testable import StarHubTHCore

/// Le dossier **réel** d'un mod dont on ne connaît que le nom logique.
///
/// Un mod en pause vit dans un dossier préfixé d'un point (`Mods/.X`), et le
/// nom logique n'en porte jamais. Toute lecture ou écriture qui compose le
/// chemin à la main manque donc un mod sur deux : **721 des dossiers du parc
/// de référence sont en pause** (mesuré le 2026-09-11).
struct ModRootResolverTests {

    private func fixture(_ directories: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mod-root-\(UUID().uuidString)", isDirectory: true)
        for relative in directories {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(relative, isDirectory: true),
                withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func anActiveModIsFoundUnderItsPlainName() throws {
        let mods = try fixture(["SVE"])
        defer { try? FileManager.default.removeItem(at: mods) }

        #expect(ModRootResolver.physicalRoot(of: "SVE", modsRoot: mods.path)
                == mods.appendingPathComponent("SVE").path)
    }

    @Test func aPausedModIsFoundUnderItsDottedName() throws {
        // Le cas le plus fréquent du parc : 721 dossiers sur ~1 700.
        let mods = try fixture([".SVE"])
        defer { try? FileManager.default.removeItem(at: mods) }

        #expect(ModRootResolver.physicalRoot(of: "SVE", modsRoot: mods.path)
                == mods.appendingPathComponent(".SVE").path)
    }

    @Test func theActiveFormWinsWhenBothExist() throws {
        // Les deux peuvent coexister — c'est un cas réel du parc, et c'est la
        // forme **active** que SMAPI lit.
        let mods = try fixture(["SVE", ".SVE"])
        defer { try? FileManager.default.removeItem(at: mods) }

        #expect(ModRootResolver.physicalRoot(of: "SVE", modsRoot: mods.path)
                == mods.appendingPathComponent("SVE").path)
    }

    @Test func aComponentOfAPausedPackIsFoundThroughItsHead() throws {
        // ⚠️ **Le point vit sur l'entrée de tête** : mettre un pack en pause
        // renomme `Mods/Pack`, pas ses composants. Mesuré sur le parc le
        // 2026-09-11 — 721 dossiers en pause à la racine, et **un seul**
        // dossier pointé au niveau 2, qui n'est pas un mod
        // (`.ModCollectionAlbum/.config`).
        let mods = try fixture([".Pack/Composant"])
        defer { try? FileManager.default.removeItem(at: mods) }

        #expect(ModRootResolver.physicalRoot(of: "Pack/Composant", modsRoot: mods.path)
                == mods.appendingPathComponent(".Pack/Composant").path)
    }

    @Test func aComponentPausedOnItsOwnIsStillFound() throws {
        // Le parc n'en porte aucun, mais rien n'empêche l'utilisateur d'en
        // créer un à la main : chaque niveau est essayé actif puis en pause.
        let mods = try fixture(["Pack/.Composant"])
        defer { try? FileManager.default.removeItem(at: mods) }

        #expect(ModRootResolver.physicalRoot(of: "Pack/Composant", modsRoot: mods.path)
                == mods.appendingPathComponent("Pack/.Composant").path)
    }

    @Test func aMissingComponentGivesUpRatherThanGuessing() throws {
        // `nil` dit « ce mod n'est pas là ». Rendre un chemin plausible ferait
        // écrire à côté — dans un dossier qui n'existe pas, ou pire, dans un
        // autre mod.
        let mods = try fixture([".Pack"])
        defer { try? FileManager.default.removeItem(at: mods) }

        #expect(ModRootResolver.physicalRoot(of: "Pack/Composant", modsRoot: mods.path) == nil)
    }

    @Test func anAbsentModIsNotResolved() throws {
        let mods = try fixture([])
        defer { try? FileManager.default.removeItem(at: mods) }

        #expect(ModRootResolver.physicalRoot(of: "SVE", modsRoot: mods.path) == nil)
    }

    @Test func aLogicalNameNeverCarriesTheDotItself() throws {
        // Si un appelant passait déjà le nom physique, on ne doit pas chercher
        // `..SVE`.
        let mods = try fixture([".SVE"])
        defer { try? FileManager.default.removeItem(at: mods) }

        #expect(ModRootResolver.physicalRoot(of: ".SVE", modsRoot: mods.path)
                == mods.appendingPathComponent(".SVE").path)
    }
}
