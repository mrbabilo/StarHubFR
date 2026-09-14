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

/// **Les libellés du chemin partagé suivent l'action.**
///
/// Relevé le 2026-09-14 sur une désinstallation réelle : l'écran annonçait
/// « Téléchargement de SMAPI… », puis « Préparation de l'installation de
/// SMAPI… », et un échec s'y serait dit « Erreur d'installation ». Le code
/// est partagé entre les deux actions ; les mots ne doivent pas l'être.
@Suite struct SmapiInstallerActionMessagesTests {

    @Test func installKeepsTheInstallWording() {
        #expect(SmapiInstallerAction.install.downloadingMessageKey == "smapi_downloading")
        #expect(SmapiInstallerAction.install.preparingMessageKey == "smapi_preparing")
        #expect(SmapiInstallerAction.install.genericFailureMessageKey == "smapi_install_error")
    }

    @Test func uninstallNeverSaysInstall() {
        #expect(SmapiInstallerAction.uninstall.downloadingMessageKey == "smapi_downloading_uninstall")
        #expect(SmapiInstallerAction.uninstall.preparingMessageKey == "smapi_preparing_uninstall")
        #expect(SmapiInstallerAction.uninstall.genericFailureMessageKey == "smapi_uninstall_failed")
    }

    /// Le vrai invariant, celui qui tient même si les clés sont renommées :
    /// aucune des trois clés d'une désinstallation ne doit valoir celle de
    /// l'installation. C'est exactement le défaut d'origine — trois clés
    /// partagées par les deux actions.
    @Test func theTwoActionsShareNoSharedPathKey() {
        for pair in [
            (SmapiInstallerAction.install.downloadingMessageKey,
             SmapiInstallerAction.uninstall.downloadingMessageKey),
            (SmapiInstallerAction.install.preparingMessageKey,
             SmapiInstallerAction.uninstall.preparingMessageKey),
            (SmapiInstallerAction.install.genericFailureMessageKey,
             SmapiInstallerAction.uninstall.genericFailureMessageKey)
        ] {
            #expect(pair.0 != pair.1)
        }
    }
}
