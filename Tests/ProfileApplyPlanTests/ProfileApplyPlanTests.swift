import Foundation
import Testing
@testable import StarHubTHCore

/// Un mod de tête, tel que `scanMods` le rend : `folderName` **logique**
/// (jamais de point), le point vivant dans `physicalFolderName`.
private func makeMod(_ folderName: String,
                     uniqueId: String? = nil,
                     enabled: Bool,
                     children: [ModItem]? = nil) -> ModItem {
    ModItem(uniqueId: uniqueId ?? folderName.lowercased(),
            name: folderName,
            folderName: folderName,
            version: "1.0.0",
            author: "Auteur",
            description: "",
            nexusUrl: "",
            nexusModId: "",
            isEnabled: enabled,
            dependencies: [],
            children: children,
            isGroup: children != nil)
}

/// Ce que `FileManager.moveItem` fait vraiment : il **échoue** si la
/// destination existe — il n'écrase pas. Le simulateur applique donc les
/// déplacements dans l'ordre du plan, en refusant ceux dont la destination est
/// occupée par un autre dossier au moment où ils passent.
private func simulate(_ moves: [ProfileApplyPlan.Move],
                      on mods: [ModItem]) -> (mods: [ModItem], refused: [ProfileApplyPlan.Move]) {
    var state = mods
    var occupied = Set(state.map(\.physicalFolderName))
    var refused: [ProfileApplyPlan.Move] = []

    for move in moves {
        guard !occupied.contains(move.destination) else {
            refused.append(move)
            continue
        }
        guard let index = state.firstIndex(where: { $0.physicalFolderName == move.source }) else {
            refused.append(move)
            continue
        }
        occupied.remove(move.source)
        occupied.insert(move.destination)
        state[index].isEnabled = (move.direction == .enable)
    }
    return (state, refused)
}

@Suite struct ProfileApplyPlanTests {

    // MARK: - Ce que le plan demande

    /// Un mod actif que le profil ne réclame pas part en pause : `Mods/X` →
    /// `Mods/.X`, le renommage par préfixe point.
    @Test func anEnabledModOutsideTheProfileIsMovedAside() {
        let mods = [makeMod("Alpha", enabled: true)]
        let profile = ModProfile(name: "Solo", enabledModIds: [])

        let moves = ProfileApplyPlan.moves(applying: profile, to: mods)

        #expect(moves.count == 1)
        #expect(moves.first?.source == "Alpha")
        #expect(moves.first?.destination == ".Alpha")
        #expect(moves.first?.direction == .disable)
    }

    /// Un mod en pause que le profil réclame revient : `Mods/.X` → `Mods/X`.
    @Test func aPausedModTheProfileAsksForIsBroughtBack() {
        let mods = [makeMod("Alpha", enabled: false)]
        let profile = ModProfile(name: "Solo", enabledModIds: ["alpha"])

        let moves = ProfileApplyPlan.moves(applying: profile, to: mods)

        #expect(moves.map(\.source) == [".Alpha"])
        #expect(moves.map(\.destination) == ["Alpha"])
        #expect(moves.first?.direction == .enable)
    }

    /// Un mod déjà du bon côté ne bouge pas — c'est ce qui rend un double
    /// clic inoffensif.
    @Test func aModAlreadyOnTheRightSideDoesNotMove() {
        let mods = [makeMod("Alpha", enabled: true), makeMod("Beta", enabled: false)]
        let profile = ModProfile(name: "Solo", enabledModIds: ["alpha"])

        #expect(ProfileApplyPlan.moves(applying: profile, to: mods).isEmpty)
    }

    /// Un profil ne connaît que des `UniqueID`. Un mod dont le manifeste n'en
    /// déclare pas ne peut donc **jamais** y figurer : le balayer dans les
    /// mods en pause à chaque application serait une perte silencieuse. Sur le
    /// parc de référence, 111 mods sont dans ce cas.
    @Test func aModWithoutAUniqueIdIsLeftExactlyWhereItIs() {
        let mods = [makeMod("Anonyme", uniqueId: "", enabled: true)]
        let profile = ModProfile(name: "Solo", enabledModIds: ["alpha"])

        #expect(ProfileApplyPlan.moves(applying: profile, to: mods).isEmpty)
    }

    /// Un pack bascule en entier dès qu'**un** de ses composants est au
    /// profil : le dossier du pack est la seule chose qui se renomme.
    @Test func aPackMovesWholeWhenAnyOfItsComponentsIsInTheProfile() {
        let child = makeMod("Pack/Composant", uniqueId: "child.mod", enabled: false)
        let pack = makeMod("Pack", uniqueId: "", enabled: false, children: [child])
        let profile = ModProfile(name: "Solo", enabledModIds: ["child.mod"])

        let moves = ProfileApplyPlan.moves(applying: profile, to: [pack])

        #expect(moves.map(\.source) == [".Pack"])
        #expect(moves.map(\.destination) == ["Pack"])
    }

    /// Les mises en pause passent **avant** les activations : c'est ce qui
    /// libère un nom de dossier avant qu'un autre mod ne le réclame.
    @Test func modsAreSetAsideBeforeOthersAreBroughtBack() {
        let mods = [makeMod("Alpha", enabled: false), makeMod("Beta", enabled: true)]
        let profile = ModProfile(name: "Solo", enabledModIds: ["alpha"])

        let moves = ProfileApplyPlan.moves(applying: profile, to: mods)

        #expect(moves.map(\.direction) == [.disable, .enable])
    }

    /// Le plan porte le nom **logique** et le nom affiché : le premier est la
    /// clé des magasins persistés, le second va dans l'alerte de fin.
    @Test func eachMoveCarriesTheLogicalFolderNameAndTheDisplayName() {
        let mods = [makeMod("Alpha", enabled: true)]
        let profile = ModProfile(name: "Solo", enabledModIds: [])

        let move = ProfileApplyPlan.moves(applying: profile, to: mods).first

        #expect(move?.folderName == "Alpha")
        #expect(move?.modName == "Alpha")
    }

    // MARK: - Idempotence (R6)

    /// La propriété que R6 demande, sur un cas nommé : appliquer deux fois un
    /// même profil = l'appliquer une fois.
    @Test func applyingTheSameProfileTwiceChangesNothingTheSecondTime() {
        let mods = [makeMod("Alpha", enabled: true),
                    makeMod("Beta", enabled: false),
                    makeMod("Gamma", enabled: true)]
        let profile = ModProfile(name: "Solo", enabledModIds: ["beta", "gamma"])

        let first = simulate(ProfileApplyPlan.moves(applying: profile, to: mods), on: mods)
        #expect(first.refused.isEmpty)
        #expect(ProfileApplyPlan.moves(applying: profile, to: first.mods).isEmpty)
    }

    /// La même propriété, sur 200 parcs engendrés — dont des packs, des mods
    /// sans identifiant et des noms de dossier qui se répètent. Générateur
    /// déterministe : un échec est rejouable tel quel.
    @Test func theSecondApplicationIsAlwaysANoOpOnGeneratedLibraries() {
        var rng = SeededGenerator(seed: 0xB0_1D_5E_ED)

        for round in 0..<200 {
            let (mods, profile) = makeLibrary(using: &rng)
            let first = simulate(ProfileApplyPlan.moves(applying: profile, to: mods), on: mods)
            let second = ProfileApplyPlan.moves(applying: profile, to: first.mods)

            // Ce qui reste à faire au second tour ne peut être que ce que le
            // disque a refusé au premier — jamais un déplacement neuf, et
            // jamais le retour en arrière d'un déplacement réussi.
            #expect(Set(second.map(\.source)) == Set(first.refused.map(\.source)),
                    "tour \(round) : le second plan ne recouvre pas les refus du premier")

            // Et le troisième tour n'apporte rien de plus que le second : le
            // système est stable, pas oscillant.
            let third = simulate(second, on: first.mods)
            #expect(third.mods.map(\.physicalFolderName) == first.mods.map(\.physicalFolderName),
                    "tour \(round) : la troisième passe a encore bougé quelque chose")
        }
    }

    /// Le cas qui met la propriété en défaut sans être un bug : `X` actif et
    /// `.X` en pause sont **deux mods différents** (cas réel du parc :
    /// `[CP] Seaside Sounds` de witchtopia et celui de Liana). Un profil qui
    /// réclame le second et pas le premier demande un échange de noms, que
    /// deux renommages ne peuvent pas faire : les deux échouent, aucun octet
    /// n'est perdu, et l'alerte de fin nomme les deux mods.
    @Test func twoModsSharingAFolderNameDeadlockWithoutLosingAnything() {
        let active = makeMod("Seaside", uniqueId: "witchtopia.seaside", enabled: true)
        let paused = makeMod("Seaside", uniqueId: "liana.seaside", enabled: false)
        let profile = ModProfile(name: "Solo", enabledModIds: ["liana.seaside"])

        let moves = ProfileApplyPlan.moves(applying: profile, to: [active, paused])
        #expect(moves.count == 2)

        let outcome = simulate(moves, on: [active, paused])
        #expect(outcome.refused.count == 2)
        #expect(outcome.mods.map(\.physicalFolderName) == ["Seaside", ".Seaside"])
    }
}

// MARK: - Générateur

/// Générateur déterministe (xorshift64*) : la suite ne dépend ni de la
/// plateforme ni de l'ordre des tests, donc un échec se rejoue.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}

/// Un parc engendré et un profil qui en réclame une partie. L'alphabet des
/// noms de dossier est volontairement court : les collisions `X` / `.X` — le
/// cas que le parc réel porte — doivent tomber d'elles-mêmes.
private func makeLibrary(using rng: inout SeededGenerator) -> ([ModItem], ModProfile) {
    let names = ["Alpha", "Beta", "Gamma", "Delta"]
    let count = Int.random(in: 1...8, using: &rng)
    var mods: [ModItem] = []
    // Le disque ne peut pas porter deux fois le même nom **physique** : `X` et
    // `.X` cohabitent, `X` et `X` non. Un parc qui l'oublierait ferait échouer
    // la propriété sur un état que macOS n'a jamais rendu.
    var taken: Set<String> = []

    for index in 0..<count {
        let folder = names[Int.random(in: 0..<names.count, using: &rng)]
        let enabled = Bool.random(using: &rng)
        let physical = (enabled ? "" : ".") + folder
        guard taken.insert(physical).inserted else { continue }
        switch Int.random(in: 0..<10, using: &rng) {
        case 0:
            // Un mod sans identifiant : le profil ne peut pas le porter.
            mods.append(makeMod(folder, uniqueId: "", enabled: enabled))
        case 1, 2:
            // Un pack : en-tête sans identifiant, deux composants.
            let children = [makeMod("\(folder)/Un", uniqueId: "child\(index).a", enabled: enabled),
                            makeMod("\(folder)/Deux", uniqueId: "child\(index).b", enabled: enabled)]
            mods.append(makeMod(folder, uniqueId: "", enabled: enabled, children: children))
        default:
            mods.append(makeMod(folder, uniqueId: "mod\(index)", enabled: enabled))
        }
    }

    // Le profil pioche parmi les identifiants réellement présents, plus
    // parfois un identifiant absent du disque (un mod désinstallé depuis).
    var enabledIds: [String] = []
    for mod in mods {
        for candidate in (mod.children ?? [mod]) where !candidate.uniqueId.isEmpty {
            if Bool.random(using: &rng) { enabledIds.append(candidate.uniqueId) }
        }
    }
    if Int.random(in: 0..<4, using: &rng) == 0 { enabledIds.append("disparu.mod") }

    return (mods, ModProfile(name: "Engendré", enabledModIds: enabledIds))
}
