import Testing
import Foundation
@testable import StarHubTHCore

/// D2-T3 §6 — fixtures content.json. Content Patcher n'a ni clé racine
/// `Include` ni `DynamicChanges` : une inclusion est un patch de `Changes`
/// (`"Action": "Include"`, `FromFile` = liste à virgules, chemins depuis la
/// racine du pack). Mesuré sur le vrai parc le 2026-10-07 : 1 103 patches
/// Include, 134 listes multiples, 2 446 chemins tous résolus depuis la racine,
/// 0 clé racine `Include`/`DynamicChanges`.
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
        // L'Include remplace son patch par le contenu du fichier : 1 + 2.
        let root = #"{"Format": "2.5.0", "Changes": [{"Action": "Load"}, {"Action": "Include", "FromFile": "inc.json"}]}"#
        let inc = #"{"Changes": [{"Action": "EditMap"}, {"Action": "EditMap"}]}"#
        var fed: [String] = []
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root) { path in
            fed.append(path)
            return path == "inc.json" ? inc : nil
        }
        #expect(result.patches == 3)
        #expect(result.includesRead == 1)
        #expect(result.includesUnread == 0)
        #expect(fed == ["inc.json"])
    }

    @Test func includeCommaListFromRealSVE() {
        // Extrait de « [CP] Stardew Valley Expanded/content.json » : liste à
        // virgules, espaces doubles, virgule traînante après le dernier champ.
        let root = """
        {
          "Changes": [
            // INCLUDES
            {
              "Action": "Include",
              "FromFile": "code/npcs/victor.json, code/npcs/olivia.json,code/npcs/susan.json,  code/npcs/andy.json ",
            },
          ]
        }
        """
        var fed: [String] = []
        let result = ContentPatcherPacks.count(packName: "SVE", contentJSON: root) { path in
            fed.append(path)
            return #"{"Changes": [{"Action": "EditData"}]}"#
        }
        #expect(fed == ["code/npcs/victor.json", "code/npcs/olivia.json",
                        "code/npcs/susan.json", "code/npcs/andy.json"])
        #expect(result.patches == 4)
        #expect(result.includesRead == 4)
    }

    @Test func actionAndFieldNamesAreCaseInsensitiveLikeCP() {
        let root = #"{"changes": [{"action": "include", "fromFile": "a.json"}]}"#
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root) { _ in
            #"{"Changes": [{"Action": "Load"}]}"#
        }
        #expect(result.patches == 1)
        #expect(result.includesRead == 1)
    }

    @Test func nestedIncludeResolvesFromPackRoot() {
        // CP résout FromFile depuis la racine du pack, jamais depuis le
        // fichier qui inclut (2 446 chemins sur 2 446 dans le vrai parc).
        let root = #"{"Changes": [{"Action": "Include", "FromFile": "sub/a.json"}]}"#
        let a = #"{"Changes": [{"Action": "Load"}, {"Action": "Include", "FromFile": "other/b.json"}]}"#
        let b = #"{"Changes": [{"Action": "Load"}]}"#
        var fed: [String] = []
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root) { path in
            fed.append(path)
            switch path {
            case "sub/a.json": return a
            case "other/b.json": return b
            default: return nil
            }
        }
        #expect(fed == ["sub/a.json", "other/b.json"])
        #expect(result.patches == 2)
        #expect(result.includesRead == 2)
    }

    @Test func includeCycleTerminates() {
        // a → b → a : le second « a.json » est déjà lu, la boucle se ferme.
        let a = #"{"Changes": [{"Action": "Load"}, {"Action": "Include", "FromFile": "b.json"}]}"#
        let b = #"{"Changes": [{"Action": "Load"}, {"Action": "Include", "FromFile": "a.json"}]}"#
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: a) { $0 == "b.json" ? b : a }
        #expect(result.state == .ok)
        #expect(result.patches == 3)
        #expect(result.includesRead == 2)
    }

    @Test func includeDepthCap() {
        // Chaîne de 7 fichiers : la profondeur max 5 coupe avant la fin.
        func file(_ n: Int) -> String {
            n >= 7 ? #"{"Changes": [{"Action": "Load"}]}"#
                   : #"{"Changes": [{"Action": "Load"}, {"Action": "Include", "FromFile": "f\#(n + 1).json"}]}"#
        }
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: file(0)) { path in
            let digits = path.dropFirst().prefix(while: \.isNumber)
            return file(Int(digits) ?? -1)
        }
        #expect(result.includesRead == ContentPatcherPacks.maxIncludeDepth)
        // f0 lui-même + les 5 inclusions suivies avant la coupure.
        #expect(result.patches == ContentPatcherPacks.maxIncludeDepth + 1)
        #expect(result.state == .ok)
    }

    @Test func tokenPathAndBrokenIncludeAreCountedUnread() {
        // Un chemin à jeton ne se résout pas hors du jeu ; un fichier inclus
        // illisible non plus. Les deux restent visibles, jamais muets.
        let root = #"{"Changes": [{"Action": "Include", "FromFile": "{{Season}}.json, broken.json"}]}"#
        var fed: [String] = []
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root) { path in
            fed.append(path)
            return "{oops"
        }
        #expect(fed == ["broken.json"])
        #expect(result.state == .ok)
        #expect(result.patches == 0)
        #expect(result.includesRead == 0)
        #expect(result.includesUnread == 2)
    }

    @Test func brokenJSONIsIllisibleNeverInvented() {
        let result = ContentPatcherPacks.count(packName: "[CP] Cassé", contentJSON: "{oops", includeLoader: { _ in nil })
        #expect(result.state == .illisible)
        #expect(result.patches == 0)
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

    @Test func crlfCommentDoesNotHideTheRestOfTheFile() {
        // Swift regroupe `\r\n` en un seul Character. Un parseur par Character
        // qui cherche seulement `\n` avale donc tout après le premier `//`.
        let text = "{\r\n// section\r\n\"Changes\": [{\"Action\": \"Load\"}]\r\n}"
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: text,
                                               includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 1)
    }

    @Test func trailingCommaBeforeCommentAndClosingBracketIsTolerated() {
        // Après retrait du commentaire, la virgule devient traînante. Les deux
        // nettoyages doivent donc être des passes distinctes.
        let text = """
        {
            "Changes": [
                {"Action": "Load"},
                // fin de section
            ]
        }
        """
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: text,
                                               includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 1)
    }

    @Test func barePropertyNameAcceptedLikeNewtonsoft() {
        let text = #"{Format: "2.0.0", Changes: [{Action: "Load"}]}"#
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: text,
                                               includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 1)
    }

    @Test func rawNewlineInsideStringAcceptedLikeNewtonsoft() {
        let text = "{\"Changes\": [{\"Action\": \"EditData\", \"Text\": \"line one\nline two\"}]}"
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: text,
                                               includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 1)
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
        // Cas réel : 5 inclusions conditionnelles vers des mods absents du parc.
        let root = #"{"Changes": [{"Action": "Load"}, {"Action": "Include", "FromFile": "gone.json"}]}"#
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root, includeLoader: { _ in nil })
        #expect(result.state == .ok)
        #expect(result.patches == 1)
        #expect(result.includesRead == 0)
        #expect(result.includesUnread == 0)
    }

    @Test func groupTotalSumsOnlyReadablePacks() {
        let group = ContentPatcherPacks.Group(rootName: "SVE", packs: [
            ContentPatcherPackCount(packName: "[CP] SVE", patches: 120, includesRead: 2, includesUnread: 0, loadTargets: [], state: .ok),
            ContentPatcherPackCount(packName: "[FTM] SVE", patches: 0, includesRead: 0, includesUnread: 0, loadTargets: [], state: .illisible),
        ])
        #expect(group.totalPatches == 120)
    }

    // MARK: - A5-T4 — cibles Load certaines et paires

    @Test func onlyUnconditionalExclusiveUntokenizedLoadsClaimATarget() {
        func targets(_ json: String) -> Set<String> {
            ContentPatcherPacks.count(packName: "P", contentJSON: json, includeLoader: { _ in nil }).loadTargets
        }
        #expect(targets(#"{"Changes": [{"Action": "Load", "Target": "Maps/Town"}]}"#) == ["maps/town"])
        // Conditionnel, priorité déclarée, jeton : aucun n'est certain.
        #expect(targets(#"{"Changes": [{"Action": "Load", "Target": "Maps/Town", "When": {"Season": "spring"}}]}"#).isEmpty)
        #expect(targets(#"{"Changes": [{"Action": "Load", "Target": "Maps/Town", "Priority": "High"}]}"#).isEmpty)
        #expect(targets(#"{"Changes": [{"Action": "Load", "Target": "Maps/{{Season}}"}]}"#).isEmpty)
        // Multi-cibles « A|B » et « A,B » : chacune réclamée, casse pliée.
        #expect(targets(#"{"Changes": [{"Action": "Load", "Target": "Maps/Town | portraits/Abigail,x"}]}"#)
                == ["maps/town", "portraits/abigail", "x"])
        // Le cas voisin qui ne doit PAS fusionner : un Load à jeton d'un côté
        // ne réclame rien, même si l'autre pack vise la même cible en clair.
        #expect(targets(#"{"Changes": [{"Action": "Load", "Target": "Maps/{{Season}}"}, {"Action": "EditData", "Target": "Maps/Town"}]}"#).isEmpty)
    }

    @Test func aConditionalIncludeMakesEverythingItLoadsUncertain() {
        // Le cas voisin qui ne doit PAS réclamer : un Load nu dans un fichier
        // inclus sous condition (patron « Seasonal Include » de SVE).
        let root = #"{"Changes": [{"Action": "Include", "FromFile": "inc.json", "When": {"Season": "spring"}}]}"#
        let inc = #"{"Changes": [{"Action": "Load", "Target": "Maps/Town"}, {"Action": "Include", "FromFile": "deep.json"}]}"#
        let deep = #"{"Changes": [{"Action": "Load", "Target": "Maps/Beach"}]}"#
        let result = ContentPatcherPacks.count(packName: "P", contentJSON: root) {
            $0 == "inc.json" ? inc : ($0 == "deep.json" ? deep : nil)
        }
        #expect(result.loadTargets.isEmpty)
        #expect(result.patches == 2)                    // compté, mais incertain
    }

    @Test func explicitExclusiveStaysCertainAndBackslashesFold() {
        let json = #"{"Changes": [{"Action": "Load", "Target": "Portraits\\Haley", "Priority": "Exclusive"}]}"#
        #expect(ContentPatcherPacks.count(packName: "P", contentJSON: json, includeLoader: { _ in nil }).loadTargets
                == ["portraits/haley"])
    }

    @Test func loadTargetsFollowIncludes() {
        let root = #"{"Changes": [{"Action": "Include", "FromFile": "inc.json"}]}"#
        let inc = #"{"Changes": [{"Action": "Load", "Target": "Maps/Town"}]}"#
        #expect(ContentPatcherPacks.count(packName: "P", contentJSON: root) { $0 == "inc.json" ? inc : nil }
               .loadTargets == ["maps/town"])
    }

    @Test func pairsNeedTwoRootsAndFlagDormantOnes() {
        let packs: [ContentPatcherLoadTargets.Pack] = [
            .init(rootName: "A", packName: "[CP] A", rootEnabled: true,
                  loadTargets: ["maps/town", "portraits/haley"]),
            .init(rootName: "B", packName: "[CP] B", rootEnabled: true,
                  loadTargets: ["maps/town"]),
            .init(rootName: "C", packName: "[CP] C", rootEnabled: false,
                  loadTargets: ["portraits/haley"]),
        ]
        let pairs = ContentPatcherLoadTargets.pairs(packs)
        #expect(pairs.count == 2)                       // maps/town active, portraits/haley dormante
        #expect(pairs.contains { $0.asset == "maps/town" && $0.bothActive })
        #expect(pairs.contains { $0.asset == "portraits/haley" && !$0.bothActive })
        // Deux packs du même mod ne sont pas une paire d'utilisateur.
        let sameRoot: [ContentPatcherLoadTargets.Pack] = [
            .init(rootName: "A", packName: "[CP] A1", rootEnabled: true, loadTargets: ["x/y"]),
            .init(rootName: "A", packName: "[CP] A2", rootEnabled: true, loadTargets: ["x/y"]),
            .init(rootName: "B", packName: "[CP] B", rootEnabled: true, loadTargets: []),
        ]
        #expect(ContentPatcherLoadTargets.pairs(sameRoot).isEmpty)
    }
}
