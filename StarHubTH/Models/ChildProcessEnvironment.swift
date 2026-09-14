import Foundation

/// L'environnement d'un processus enfant dont on **lit la sortie**.
///
/// Deux exigences qui se contredisent en apparence :
///
/// 1. **La locale doit être POSIX.** Nos parseurs lisent des messages en
///    anglais (`unzip -l` et son « 3 files », les verdicts « SMAPI is
///    installed! »). Sous la locale d'un utilisateur francophone, ces lignes
///    sont traduites et le parseur échoue en silence — c'est AGENTS §4.7.
/// 2. **Le reste de l'environnement doit survivre.** Un enfant en lance
///    souvent un autre *par son nom nu* : l'installateur SMAPI démarre
///    `chmod`, sans chemin absolu. Sans `PATH`, .NET ne le résout pas — et,
///    contrairement à `execvp(3)`, **il ne retombe sur aucun chemin par
///    défaut**.
///
/// Mesuré le 2026-09-14, pile .NET à l'appui (l'installateur imprime son
/// exception entière) :
///
/// ```
/// System.ComponentModel.Win32Exception (2): An error occurred trying to start
/// process 'chmod' with working directory '/'. No such file or directory
///    at ... InteractiveInstaller.cs:line 407
/// ```
///
/// L'installation de SMAPI depuis l'app était cassée depuis le 2026-09-07
/// (`530459b9`), et elle échouait **à moitié faite** : fichiers cœur copiés,
/// lanceur déjà remplacé, `StardewModdingAPI.deps.json` et les mods groupés
/// jamais posés — le jeu ne démarrait plus.
///
/// ⚠️ **Un seul endroit construit cet environnement.** Il en existait deux :
/// `ModZipInstaller` héritait correctement, `SmapiInstaller` remplaçait tout.
/// Les deux copies lisaient la même règle, une seule la tenait — la forme
/// exacte que ce dépôt a déjà payée ailleurs.
public enum ChildProcessEnvironment {

    /// L'environnement du parent, avec la locale verrouillée.
    ///
    /// - Parameters:
    ///   - locale: la valeur posée sur `LANG` **et** `LC_ALL` — `"C"` ou
    ///     `"en_US_POSIX"` selon l'appelant ; `LC_ALL` l'emporte de toute
    ///     façon sur les autres `LC_*` hérités.
    ///   - parent: l'environnement à hériter. Injecté pour les tests ; la
    ///     production passe celui du processus.
    public static func localeLocked(
        to locale: String,
        inheriting parent: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = parent
        env["LANG"] = locale
        env["LC_ALL"] = locale
        return env
    }
}
