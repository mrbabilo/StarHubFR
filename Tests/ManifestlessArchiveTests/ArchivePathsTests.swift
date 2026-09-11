import Foundation
import Testing
@testable import StarHubTHCore

/// Les chemins d'une archive dépliée — ce que `ManifestlessArchive.classify`
/// reçoit, et que rien ne vérifiait.
///
/// La fonction vivait `static` sur le ViewModel, appelée jusque depuis une
/// vue : hors de portée des tests alors qu'elle produit **l'entrée** de tout
/// le classement d'un dépôt. Une liste vide ici, et une archive parfaitement
/// valide devient « contenu non reconnu ».
struct ArchivePathsTests {

    private func fixture(_ files: [String], directories: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for relative in files {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        for relative in directories {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(relative, isDirectory: true),
                withIntermediateDirectories: true)
        }
        return root
    }

    @Test func pathsAreRelativeToTheRoot() throws {
        let root = try fixture(["i18n/fr.json", "manifest.json"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ManifestlessArchive.paths(under: root).sorted()
                == ["i18n/fr.json", "manifest.json"])
    }

    /// ⚠️ **Le piège `/var` ↔ `/private/var`.** `FileManager.enumerator` rend
    /// des URLs dont les liens symboliques sont suivis, alors que la racine
    /// passée peut ne pas l'être. Les deux formes désignent le **même**
    /// dossier, et la fonction doit rendre la même chose pour l'une et pour
    /// l'autre — `resolvingSymlinksInPath()` les normalise en *retirant* le
    /// préfixe `/private` (il ne l'ajoute jamais). Sans cette normalisation
    /// **des deux côtés**, le préfixe ne correspond pas et la liste sort
    /// **vide** : une archive parfaitement valide devient « contenu non
    /// reconnu », sans erreur ni journal.
    @Test func bothFormsOfTheSameRootYieldTheSameFiles() throws {
        let root = try fixture(["assets/a.png"])
        defer { try? FileManager.default.removeItem(at: root) }
        // `temporaryDirectory` rend la forme courte (`/var/folders/…`) ; son
        // jumeau physique est le même chemin sous `/private`.
        let viaPrivate = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
        try #require(FileManager.default.fileExists(atPath: viaPrivate.path),
                     "la fixture ne passe par aucun lien : ce test n'éprouverait rien")

        #expect(ManifestlessArchive.paths(under: root) == ["assets/a.png"])
        #expect(ManifestlessArchive.paths(under: viaPrivate) == ["assets/a.png"])
    }

    @Test func nestedFilesAreWalkedToTheBottom() throws {
        let root = try fixture(["[CP] Pack/assets/season/spring.png"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ManifestlessArchive.paths(under: root) == ["[CP] Pack/assets/season/spring.png"])
    }

    @Test func directoriesAreNotPaths() throws {
        // `classify` raisonne sur des fichiers : compter les dossiers ferait
        // voir des entrées qu'aucun dépôt ne posera.
        let root = try fixture(["i18n/fr.json"], directories: ["assets/empty"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ManifestlessArchive.paths(under: root) == ["i18n/fr.json"])
    }

    @Test func hiddenFilesAreSkipped() throws {
        // `.DS_Store` et `__MACOSX` voyagent dans presque toutes les archives
        // faites sur macOS : les déposer dans le mod de l'utilisateur, puis
        // les inscrire au registre comme des fichiers à retirer, serait faux
        // deux fois.
        let root = try fixture(["i18n/fr.json", ".DS_Store"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ManifestlessArchive.paths(under: root) == ["i18n/fr.json"])
    }

    @Test func anAbsentRootYieldsNothingRatherThanFailing() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)", isDirectory: true)
        #expect(ManifestlessArchive.paths(under: missing).isEmpty)
    }
}
