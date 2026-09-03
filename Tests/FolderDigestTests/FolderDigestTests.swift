import Foundation
import Testing
@testable import StarHubTHCore

/// L'empreinte d'un dossier de mod. Elle sert à décider qu'une sauvegarde
/// n'apprend rien de plus qu'une autre — donc à en **supprimer** une. Elle
/// doit donc distinguer tout ce qui distingue deux états du disque.
struct FolderDigestTests {

    private func makeTree(_ files: [String: String]) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderDigestTests-\(UUID().uuidString)", isDirectory: true)
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? Data(content.utf8).write(to: url)
        }
        return root
    }

    @Test func twoIdenticalTreesShareTheirDigest() {
        let a = makeTree(["manifest.json": "{}", "i18n/fr.json": "bonjour"])
        let b = makeTree(["manifest.json": "{}", "i18n/fr.json": "bonjour"])
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(FolderDigest.of(a) != nil)
        #expect(FolderDigest.of(a) == FolderDigest.of(b))
    }

    /// Le cas qui compte : même mod, même version, une traduction modifiée
    /// entre les deux sauvegardes. Mesuré sur un parc réel — 12 doublons de
    /// version y avaient un contenu différent. Les confondre effacerait un
    /// travail de traduction.
    @Test func aChangedFileChangesTheDigest() {
        let a = makeTree(["manifest.json": "{}", "i18n/fr.json": "bonjour"])
        let b = makeTree(["manifest.json": "{}", "i18n/fr.json": "salut"])
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(FolderDigest.of(a) != FolderDigest.of(b))
    }

    /// Un fichier **en plus** distingue, même vide : c'est un état différent.
    @Test func anExtraFileChangesTheDigest() {
        let a = makeTree(["manifest.json": "{}"])
        let b = makeTree(["manifest.json": "{}", "config.json": ""])
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(FolderDigest.of(a) != FolderDigest.of(b))
    }

    /// Le **chemin** compte, pas seulement le contenu : deux fichiers de même
    /// contenu à des emplacements différents ne font pas le même mod.
    @Test func aMovedFileChangesTheDigest() {
        let a = makeTree(["i18n/fr.json": "bonjour"])
        let b = makeTree(["i18n/de.json": "bonjour"])
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(FolderDigest.of(a) != FolderDigest.of(b))
    }

    /// La part **sous-dossier** du chemin compte même entre fichiers de même
    /// nom : `x/f+A, y/g+B` et `x/g+B, y/f+A` sont deux états distincts. C'est
    /// la signature du repli `lastPathComponent` — actif quand l'énumérateur
    /// rend des chemins résolus (`/private/var/…`) que le préfixe de la racine
    /// non résolue (`/var/…`, le temporaryDirectory des tests) ne matche pas.
    @Test func theSubfolderPartOfThePathCountsEvenForSameNamedFiles() {
        let a = makeTree(["x/f.txt": "A", "y/g.txt": "B"])
        let b = makeTree(["x/g.txt": "B", "y/f.txt": "A"])
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        #expect(FolderDigest.of(a) != FolderDigest.of(b))
    }

    @Test func anAbsentFolderHasNoDigest() {
        #expect(FolderDigest.of(URL(fileURLWithPath: "/nowhere/at/all")) == nil)
    }
}
