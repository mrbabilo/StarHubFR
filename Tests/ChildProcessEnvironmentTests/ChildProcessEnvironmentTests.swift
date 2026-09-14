import Testing
@testable import StarHubTHCore

/// **Le défaut du 2026-09-14 : un enfant privé de `PATH`.**
///
/// `SmapiInstaller` rendait un environnement réduit aux deux variables de
/// locale. L'installateur SMAPI démarre `chmod` par son nom nu ; .NET ne l'a
/// pas trouvé et n'a retombé sur aucun chemin par défaut :
/// `Win32Exception (2) ... No such file or directory`. L'installation
/// s'arrêtait **après** avoir remplacé le lanceur du jeu.
@Suite struct ChildProcessEnvironmentTests {

    private let parent = [
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/Users/someone",
        "TMPDIR": "/var/folders/xx/T/",
        "LANG": "fr_FR.UTF-8",
        "LC_ALL": "fr_FR.UTF-8",
        "LC_NUMERIC": "fr_FR.UTF-8"
    ]

    @Test func thePathSurvives() {
        let env = ChildProcessEnvironment.localeLocked(to: "en_US_POSIX", inheriting: parent)
        #expect(env["PATH"] == "/usr/local/bin:/usr/bin:/bin")
    }

    @Test func theRestOfTheParentSurvivesToo() {
        let env = ChildProcessEnvironment.localeLocked(to: "C", inheriting: parent)
        #expect(env["HOME"] == "/Users/someone")
        #expect(env["TMPDIR"] == "/var/folders/xx/T/")
    }

    @Test func theLocaleIsForcedOverTheParentsOwn() {
        let env = ChildProcessEnvironment.localeLocked(to: "en_US_POSIX", inheriting: parent)
        #expect(env["LANG"] == "en_US_POSIX")
        #expect(env["LC_ALL"] == "en_US_POSIX")
    }

    /// `LC_ALL` l'emporte sur les autres `LC_*` au niveau de la libc : les
    /// laisser passer n'affaiblit rien, et les retirer reviendrait à
    /// reconstruire un environnement au lieu d'en hériter.
    @Test func otherLcVariablesTravelUntouchedBecauseLcAllOverridesThem() {
        let env = ChildProcessEnvironment.localeLocked(to: "C", inheriting: parent)
        #expect(env["LC_NUMERIC"] == "fr_FR.UTF-8")
        #expect(env["LC_ALL"] == "C")
    }

    @Test func anEmptyParentStillCarriesTheLocale() {
        let env = ChildProcessEnvironment.localeLocked(to: "C", inheriting: [:])
        #expect(env == ["LANG": "C", "LC_ALL": "C"])
    }
}
