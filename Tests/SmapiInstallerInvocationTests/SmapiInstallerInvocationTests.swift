import Testing
@testable import StarHubTHCore

/// **X32 — l'installateur SMAPI se pilote par drapeaux, pas à l'aveugle.**
///
/// Mesuré le 2026-09-06 sur le vrai binaire 4.5.2, lancé sur une installation
/// de contrôle (dossier factice contenant `Stardew Valley`,
/// `Stardew Valley.dll`, `.deps.json`, `.runtimeconfig.json`) : sous
/// `--install --game-path P`, l'installateur annonce lui-même « Just one
/// question first » — le jeu de couleurs. La question de dossier et le choix
/// d'action, que l'ancienne séquence nourrissait à l'aveugle (quatre réponses
/// d'un coup, dans un ordre supposé stable), sortent de la file. Et un
/// dossier sans jeu ne fait plus reboucler la question — l'amorce de X30 —
/// il rend « Failed finding your game path. » et sort.
@Suite struct SmapiInstallerInvocationTests {

    @Test func installCarriesItsFlagThenTheGamePath() {
        #expect(SmapiInstallerInvocation.arguments(
            action: .install,
            gamePath: "/Applications/Stardew Valley.app/Contents/MacOS"
        ) == ["--install", "--game-path", "/Applications/Stardew Valley.app/Contents/MacOS"])
    }

    @Test func uninstallCarriesItsOwnFlag() {
        #expect(SmapiInstallerInvocation.arguments(
            action: .uninstall,
            gamePath: "/Games/Stardew"
        ) == ["--uninstall", "--game-path", "/Games/Stardew"])
    }

    @Test func theGamePathTravelsVerbatimEvenWithSpaces() {
        // `Process.arguments` n'est pas un shell : l'espace du nom d'app ne
        // se cite pas, il passe brut. Le test épingle ce non-quoting — le
        // jour où quelqu'un voudra « sécuriser » la chaîne.
        let args = SmapiInstallerInvocation.arguments(
            action: .install,
            gamePath: "/Applications/Stardew Valley.app/Contents/MacOS"
        )
        #expect(args.last == "/Applications/Stardew Valley.app/Contents/MacOS")
        #expect(args.count == 3)
    }

    @Test func theOnlyRemainingQuestionIsTheColorScheme() {
        // Sous drapeaux, l'installateur ne pose plus que le jeu de couleurs ;
        // « 1 » = texte sombre sur fond clair. Mesuré : la réponse est
        // acceptée puis « That's all I need! ».
        #expect(SmapiInstallerInvocation.stdinAnswers == "1\n")
    }
}
