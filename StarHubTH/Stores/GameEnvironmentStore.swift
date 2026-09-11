import Foundation
import Observation

/// Le domaine Environnement (REFACTORING §6) : où est le jeu, qui est le
/// joueur Steam, quelle version de SMAPI est installée.
///
/// Extrait du ViewModel le 2026-09-10 — les quatre fonctions du domaine
/// n'avaient aucun appelant hors VM, et leur logique pure vit déjà en Core
/// (`SteamLoginUsers`, `GameDirLocator`, `SmapiVersionEvidence`) : ce type
/// n'est que l'état publié et le câblage.
///
/// « Ce qui n'est pas à moi arrive en paramètre » (§3) : les préférences
/// (`defaults`, comme dans `InstalledModRegistryStore`), le sélecteur de
/// dossier (`picker`) et le domicile arrivent par l'initialiseur. Le nom de
/// repli « Farmer » arrive en **closure** que l'appelant localise : le store
/// ne connaît ni L10n ni le bundle.
///
/// Threading — mêmes contrats qu'avant l'extraction : `fetchSteamUser` est
/// appelé depuis les files de fond de `refresh()`/`performInitialLoad` et
/// repasse par main pour publier ; `checkSmapiVersion` publie sur le fil de
/// l'appelant, comme avant.
@Observable
final class GameEnvironmentStore {

    /// Le dossier `Contents/MacOS` du jeu. **Ne déclenche jamais de scan** :
    /// chaque appelant qui le change relance `refresh()` lui-même. Le didSet
    /// auto-refresh d'origine lançait deux scans concurrents qui écrivaient
    /// `gameDir` et `mods` sans synchronisation — c'est l'histoire de la
    /// propriété, pas un raffinement à défaire.
    private(set) var gameDir: String = "" {
        didSet { defaults.set(gameDir, forKey: UDKey.gameDir) }
    }
    /// Nom du compte Steam le plus récent, tel que `loginusers.vdf` le dit.
    private(set) var steamUsername: String = ""
    /// Avatar local du compte (`avatarcache/<steamID>.png|.jpg`), quand il
    /// existe. Une recherche infructueuse ne l'efface pas.
    private(set) var steamAvatarPath: String?
    /// Version de SMAPI installée, ou `nil` = pas installé.
    private(set) var smapiInstalledVersion: String?

    private let defaults: UserDefaults
    private let picker: FilePicking

    init(defaults: UserDefaults = .standard, picker: FilePicking) {
        self.defaults = defaults
        self.picker = picker
    }

    // MARK: - Dossier de jeu

    /// Le chargement initial : le chemin persisté s'il existe encore, la
    /// détection Steam→GOG (`GameDirLocator`) sinon. Appelé une fois, depuis
    /// l'init du VM — synchronement, avant la première frame.
    /// `gogRoot` passe tel quel au localisateur (herméticité des tests : le
    /// vrai `/Applications` est un état de la machine).
    func restoreGameDir(home: String = NSHomeDirectory(),
                        gogRoot: String = "/Applications",
                        fm: FileManager = .default) {
        let savedPath = defaults.string(forKey: UDKey.gameDir) ?? ""
        if !savedPath.isEmpty && fm.fileExists(atPath: savedPath) {
            self.gameDir = savedPath
        } else {
            self.gameDir = GameDirLocator.detectDefault(home: home, gogRoot: gogRoot, fm: fm)
        }
    }

    /// Panneau de choix du dossier de jeu. `onPicked` porte ce qui
    /// n'appartient pas au store — le VM y relance son `refresh()`.
    ///
    /// ⚠️ Un écart d'un poil d'avec l'original, consigné au §6 : celui-ci
    /// affectait `panel.url?.path ?? ""` et relançait le scan même sur une
    /// URL `nil` après un OK. Un OK sans URL n'existe pas en pratique sur un
    /// panneau dossiers-seuls ; il vaut ici annulation — plutôt qu'un
    /// `gameDir` vidé en silence.
    func selectGameDir(onPicked: @escaping () -> Void) {
        guard let path = picker.pickDirectory() else { return }
        self.gameDir = path
        onPicked()
    }

    // MARK: - Steam

    /// Lit `loginusers.vdf` et l'avatarcache. Silence total quand le VDF est
    /// illisible : le nom déjà affiché reste (comportement historique — pas
    /// de repli « Farmer » sur un fichier absent).
    ///
    /// `fallbackFarmerName` est une **closure**, évaluée aux deux seuls
    /// endroits qui en ont besoin — le repli hors file principale, et la
    /// publication sur main. Une valeur évaluée à l'appel aurait fait lire
    /// `currentLanguage` par chaque passage sur file de fond, là où le code
    /// d'origine ne la lisait que dans ses branches rares (revue du
    /// 2026-09-10).
    func fetchSteamUser(home: String = NSHomeDirectory(),
                        systemUserName: String = NSFullUserName(),
                        fallbackFarmerName: @escaping () -> String) {
        let vdfPath = "\(home)/Library/Application Support/Steam/config/loginusers.vdf"
        guard let content = try? String(contentsOfFile: vdfPath, encoding: .utf8) else { return }
        let parsed = SteamLoginUsers.parse(content: content)

        let resolvedUsername: String
        if !parsed.personaName.isEmpty {
            resolvedUsername = parsed.personaName
        } else {
            let defaultName = systemUserName.components(separatedBy: " ").first ?? ""
            resolvedUsername = defaultName.isEmpty ? fallbackFarmerName() : defaultName
        }

        let resolvedAvatarPath = GameDirLocator.avatarPath(steamID: parsed.steamID, home: home)

        // Publication sur main. L'ordre FIFO de main garantit qu'un check
        // `isEmpty` appelant s'exécutant avant cette écriture ne peut pas
        // voir l'ancienne valeur écraser le vrai nom (audit 2026-08-05).
        DispatchQueue.main.async {
            self.steamUsername = resolvedUsername.isEmpty ? fallbackFarmerName() : resolvedUsername
            if let resolvedAvatarPath {
                self.steamAvatarPath = resolvedAvatarPath
            }
        }
    }

    // MARK: - SMAPI

    /// La version installée (`SmapiVersionEvidence.installedVersion`), ou
    /// `nil`. Deux petits fichiers lus — appel synchrone voulu, rien sur
    /// quoi l'overlay de lancement doive attendre.
    func checkSmapiVersion(home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                           fm: FileManager = .default) {
        guard !gameDir.isEmpty else {
            self.smapiInstalledVersion = nil
            return
        }
        self.smapiInstalledVersion = SmapiVersionEvidence.installedVersion(gameDir: gameDir, fm: fm, home: home)
    }
}
