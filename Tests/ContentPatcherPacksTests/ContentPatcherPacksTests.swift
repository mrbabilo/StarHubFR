import Testing
import Foundation
@testable import StarHubTHCore

/// D2-T3 §6 — fixtures content.json. Champ `DynamicChanges` : 0 occurrence
/// sur le vrai parc (mesuré 2026-10-06) mais officiel dans le format CP 2.x —
/// fixture synthétique, seul endroit où il existe.
struct ContentPatcherPacksTests {

    private func json(_ dict: [String: Any]) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: dict), encoding: .utf8)) ?? "{}"
    }

    @Test func realSmallPackThreeChanges() {
        let text = json(["Format": "2.5.0", "Changes": [["Action": "EditMap"], ["Action": "EditMap"], ["Action": "Load"]]])
        let result = ContentPatcherPacks.count(packName: "[CP] Small", contentJSON: text, includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 3)
        #expect(result.includesRead == 0)
    }

    @Test func includeOneLevel() {
        let root = json(["Format": "2.5.0", "Changes": [["Action": "Load"]], "Include": ["inc.json"]])
        let inc = json(["Changes": [["Action": "EditMap"], ["Action": "EditMap"]]])
        var fed: [String] = []
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root) { path in
            fed.append(path)
            return path == "inc.json" ? inc : nil
        }
        #expect(result.patches == 3)
        #expect(result.includesRead == 1)
        #expect(fed == ["inc.json"])
    }

    @Test func includeNestedRelativePath() {
        // Un Include dans un fichier sous-dossier se résout relativement à CE fichier.
        let root = json(["Format": "2.5.0", "Changes": [], "Include": ["sub/a.json"]])
        let a = json(["Changes": [["Action": "Load"]], "Include": ["b.json"]])
        let b = json(["Changes": [["Action": "Load"]]])
        var fed: [String] = []
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root) { path in
            fed.append(path)
            switch path {
            case "sub/a.json": return a
            case "sub/b.json": return b
            default: return nil
            }
        }
        #expect(result.patches == 2)
        #expect(result.includesRead == 2)
        #expect(fed == ["sub/a.json", "sub/b.json"])
    }

    @Test func includeCycleTerminates() {
        // Spéc §3.1 : le cycle est gardé par l'ensemble des chemins déjà lus.
        // La racine n'a pas de chemin : ré-incluse une fois (a → b → a), le
        // cycle se referme sur « b.json » déjà visité. a + b + a relu = 3
        // patches pour 2 lectures ; l'important (Review Focus 1) : ça termine.
        let a = json(["Changes": [["Action": "Load"]], "Include": ["b.json"]])
        let b = json(["Changes": [["Action": "Load"]], "Include": ["a.json"]])
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: a) { $0 == "b.json" ? b : a }
        #expect(result.state == .ok)
        #expect(result.patches == 3)
        #expect(result.includesRead == 2)
    }

    @Test func includeDepthCap() {
        // Chaîne de 7 fichiers : la profondeur max 5 coupe avant la fin.
        func file(_ n: Int) -> String {
            n >= 7 ? json(["Changes": [["Action": "Load"]]])
                   : json(["Changes": [["Action": "Load"]], "Include": ["f\(n + 1).json"]])
        }
        // Le loader doit vraiment suivre la chaîne : f0 → f1 → … → f6.
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: file(0)) { path in
            let digits = path.dropFirst().prefix(while: \.isNumber)
            return file(Int(digits) ?? -1)
        }
        #expect(result.includesRead == ContentPatcherPacks.maxIncludeDepth)
        // f0 lui-même + les 5 inclusions suivies avant la coupure.
        #expect(result.patches == ContentPatcherPacks.maxIncludeDepth + 1)
        #expect(result.state == .ok)
    }

    @Test func brokenJSONIsIllisibleNeverInvented() {
        let result = ContentPatcherPacks.count(packName: "[CP] Cassé", contentJSON: "{oops", includeLoader: { _ in nil })
        #expect(result.state == .illisible)
        #expect(result.patches == 0)
    }

    @Test func dynamicChangesOnly() {
        let text = json(["Format": "2.5.0", "DynamicChanges": [["When": [:]], ["When": [:]]]])
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: text, includeLoader: { _ in nil })
        #expect(result.patches == 2)
    }

    @Test func commentsAndTrailingCommasTolerated() {
        // CP parse content.json avec Newtonsoft : commentaires `//` et `/*…*/`
        // et virgules traînantes y sont légaux — 90 des 137 content.json du
        // vrai parc (2026-10-06) en portent, dont SVE et Ridgeside. Strict,
        // ils ressortaient `illisible` à tort.
        let text = """
        // ligne d'en-tête
        {
            /* bloc
           multi-ligne */
            "Changes": [
                {"Action": "Load"},
                {"Action": "Load"}, // fin de ligne
            ],
        }
        """
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: text, includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 2)
    }

    @Test func commentMarkersInsideStringsStay() {
        // Le nettoyage ne doit pas toucher une chaîne : une URL, un texte
        // avec `//`, `,}` ou `/*` reste entier.
        let text = #"{"Changes": [{"Action": "EditData", "Entries": {"a//b": "x,} y/*z*/"}, "When": {"url": "http://example.com/p"}, }]}"#
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: text, includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 1)
    }

    @Test func bomPrefixTolerated() {
        let text = "\u{FEFF}" + json(["Changes": [["Action": "Load"]]])
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: text, includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 1)
    }

    @Test func includeMissingFileStaysOk() {
        // Fichier inclus introuvable : SMAPI le signalera au chargement ;
        // le pack reste lisible, on ne compte que ce qu'on a lu.
        let root = json(["Changes": [["Action": "Load"]], "Include": ["gone.json"]])
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root, includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 1)
        #expect(result.includesRead == 0)
    }

    @Test func groupTotalSumsOnlyReadablePacks() {
        let group = ContentPatcherPacks.Group(rootName: "SVE", packs: [
            ContentPatcherPackCount(packName: "[CP] SVE", patches: 120, includesRead: 2, state: .ok),
            ContentPatcherPackCount(packName: "[FTM] SVE", patches: 0, includesRead: 0, state: .illisible),
        ])
        #expect(group.totalPatches == 120)
    }
}
