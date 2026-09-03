import Foundation
import Testing
@testable import StarHubTHCore

/// `ModManifest.init(dict:)` lisait les dépendances par une boucle à lui, alors
/// que `ModDependencyParser` — écrit pour le scan des mods installés — sait déjà
/// le faire, et mieux : il prend `ContentPackFor` et déduplique.
///
/// Mesuré sur le parc (2026-09-03, 1 085 manifests) : **625 déclarent un
/// `ContentPackFor`** — 254 sans aucune autre dépendance, donc annoncés « aucune
/// dépendance » à l'installation alors qu'ils exigent durement un framework, et
/// 340 avec une liste amputée de ce framework (les 31 restants le listent aussi
/// dans leurs `Dependencies` : la déduplication du parseur les couvre). Et
/// **8 manifests déclarent deux
/// fois la même dépendance** (13 lignes en double, 6 pour le seul
/// *Distant Lands*), ce qui donnait des `id` dupliqués dans un `ForEach`.
struct ManifestDependencyTests {
    private func manifest(_ body: String) -> ModManifest {
        let json = """
        { "Name": "T", "UniqueID": "test.mod", "Version": "1.0.0", "Author": "A", \(body) }
        """
        let raw = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        guard let m = ModManifest(dict: raw) else {
            Issue.record("manifest de test invalide")
            fatalError()
        }
        return m
    }

    @Test func contentPackForIsAHardDependency() {
        // La façon dont la plupart des content packs déclarent leur seule
        // exigence. L'ignorer les faisait paraître sans dépendance.
        let m = manifest("\"ContentPackFor\": { \"UniqueID\": \"Pathoschild.ContentPatcher\" }")
        #expect(m.dependencies == [ModDependency(uniqueId: "Pathoschild.ContentPatcher", isRequired: true)])
    }

    @Test func contentPackForJoinsDeclaredDependencies() {
        let m = manifest("""
        "Dependencies": [ { "UniqueID": "Foo.Bar", "IsRequired": false } ],
        "ContentPackFor": { "UniqueID": "Pathoschild.ContentPatcher" }
        """)
        #expect(m.dependencies == [
            ModDependency(uniqueId: "Foo.Bar", isRequired: false),
            ModDependency(uniqueId: "Pathoschild.ContentPatcher", isRequired: true)
        ])
    }

    @Test func aDependencyDeclaredTwiceCountsOnce() {
        // *Distant Lands - Witch Swamp Overhaul* en déclare six ainsi.
        let m = manifest("""
        "Dependencies": [
            { "UniqueID": "Lita.StarblueValley", "IsRequired": false },
            { "UniqueID": "Lita.StarblueValley", "IsRequired": false }
        ]
        """)
        #expect(m.dependencies == [ModDependency(uniqueId: "Lita.StarblueValley", isRequired: false)])
    }

    @Test func theRequiredFlagWinsOverTheOptionalOne() {
        // Aucun cas sur le parc — les 13 doublons y sont tous identiques — mais
        // garder la première occurrence affaiblirait l'exigence en silence.
        let m = manifest("""
        "Dependencies": [
            { "UniqueID": "Foo.Bar", "IsRequired": false },
            { "UniqueID": "Foo.Bar", "IsRequired": true }
        ]
        """)
        #expect(m.dependencies == [ModDependency(uniqueId: "Foo.Bar", isRequired: true)])
    }

    @Test func anIdentifierIsTrimmedBeforeUse() {
        let m = manifest("\"Dependencies\": [ { \"UniqueID\": \"  Foo.Bar \" } ]")
        #expect(m.dependencies == [ModDependency(uniqueId: "Foo.Bar", isRequired: true)])
    }

    @Test func aDependencyIsRequiredUnlessSaidOtherwise() {
        let m = manifest("\"Dependencies\": [ { \"UniqueID\": \"Foo.Bar\" } ]")
        #expect(m.dependencies == [ModDependency(uniqueId: "Foo.Bar", isRequired: true)])
    }

    @Test func aManifestWithoutDependenciesHasNone() {
        #expect(manifest("\"Description\": \"rien\"").dependencies.isEmpty)
    }
}
