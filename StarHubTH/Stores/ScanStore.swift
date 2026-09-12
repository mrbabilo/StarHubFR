import Foundation
import Observation

/// L'état du domaine Scan (chantier « vider le VM de son état publié »,
/// cadrage §3, domaine 8 — **en dernier, délibérément** : `mods` est lu par
/// presque toutes les vues et par la moitié des autres domaines).
///
/// Le lourd vit déjà en Core et testé — le balayage, la lecture des
/// manifestes, le cache mtime et **son verrou** vivent dans `ModScanner`
/// (une classe, pas une valeur : deux `scanMods()` concurrents — refresh +
/// chargement initial, activation de profil croisant un refresh manuel —
/// doivent toucher le même cache, verrouillé dedans ; le subscript non
/// protégé d'un dictionnaire est un `EXC_BAD_ACCESS` classique sous cette
/// course, crash de juillet 2026). Ce que ce store porte, c'est l'état
/// publié : le parc, la progression, l'index de duplication, les poids.
///
/// Poser le parc **prévient** — le `didSet` d'origine enchaînait trois
/// cascades inter-domaines (cache de catégories Nexus, couverture
/// française, rapport de raccourcis), câblées aujourd'hui par
/// `wireEffects`. La notification part sur **toute** affectation, même
/// identique : le `didSet` Swift ne compare pas, et une pose identique
/// reste une demande de recalcul.
@Observable
final class ScanStore {

    /// Le parc installé, prêt à afficher (ordre alphabétique de liste posé
    /// par le scanner). Écrit par `setMods` — pose + notification.
    private(set) var mods: [ModItem] = []

    /// Le progrès du scan en vol — la boucle par mod publie
    /// « Analyse de <mod>… (X/N) » ; `nil` hors scan. Inerte.
    var scanProgress: ScanProgress? = nil

    /// Les mods installés plusieurs fois, reconstruit à chaque scan.
    /// Mesuré le 2026-08-25 : 7 identifiants sur 14 dossiers, dont trois
    /// avec leurs deux copies actives (le mod Swim, à plat et dans son
    /// dossier de téléchargement).
    private(set) var duplicateIndex: ModDuplicateIndex = .empty

    /// Ce que pèsent les mods, `nil` tant qu'aucune mesure n'a abouti.
    private(set) var modsFolderSizes: ModsFolderSizes? = nil
    /// `true` pendant la traversée des poids. Le pied de barre l'annonce :
    /// sans ça, il reste vide quelques secondes au lancement, ce qui se lit
    /// comme un bug.
    private(set) var isMeasuringModsFolder = false

    /// La cascade du parc connu — l'app câble les consommateurs (le détail
    /// des trois est de l'app ; la règle testée ici est « toute pose
    /// prévient »).
    @ObservationIgnored private(set) var onModsChanged: (([ModItem]) -> Void)?

    /// Câblage après construction — la voie de l'app (le ViewModel est
    /// lui-même `@Observable` : `lazy` interdit, câblage dans son `init`).
    func wireEffects(onModsChanged: (([ModItem]) -> Void)?) {
        self.onModsChanged = onModsChanged
    }

    /// Pose le parc et **prévient**, sans garde d'égalité — fidèle au
    /// `didSet` d'origine, qui se déclenchait sur toute affectation.
    func setMods(_ newMods: [ModItem]) {
        mods = newMods
        onModsChanged?(mods)
    }

    /// Le scan reconstruit l'index de duplication à sa fin.
    func setDuplicateIndex(_ index: ModDuplicateIndex) {
        duplicateIndex = index
    }

    // MARK: - La mesure des poids : une passe à la fois

    /// Sérialise les mesures : le scan est appelé depuis 29 endroits
    /// (installation, suppression, bascule, application de profil…) et deux
    /// traversées simultanées de 100 000 fichiers ne serviraient à rien.
    @ObservationIgnored private let sizeLock = NSLock()
    @ObservationIgnored private var isSizeMeasureInFlight = false
    /// Une demande arrivée pendant une mesure n'est pas perdue : elle relance
    /// une passe à la fin, sinon le chiffre resterait celui d'avant l'action.
    @ObservationIgnored private var sizeMeasureRequestedAgain = false

    /// Prend le tour de mesure ; rend `true` si une passe est déjà en vol
    /// (et note la demande pour un rejouage).
    func beginSizeMeasure() -> Bool {
        sizeLock.withLock {
            if isSizeMeasureInFlight {
                sizeMeasureRequestedAgain = true
                return true
            }
            isSizeMeasureInFlight = true
            return false
        }
    }

    /// Clôt la passe et dit si une demande doit rejouer — le drapeau se
    /// consomme : un seul rejouage par demande.
    func endSizeMeasure() -> Bool {
        sizeLock.withLock {
            isSizeMeasureInFlight = false
            defer { sizeMeasureRequestedAgain = false }
            return sizeMeasureRequestedAgain
        }
    }

    /// Le pied de barre annonce la traversée (`isMeasuringModsFolder`).
    func setSizeMeasureRunning(_ running: Bool) {
        isMeasuringModsFolder = running
    }

    /// Le résultat atterrit — ou pas : **une mesure ratée (dossier absent)
    /// n'efface pas la précédente pendant qu'une nouvelle passe est en
    /// route** (le pied de barre garde un chiffre vraisemblable plutôt que
    /// de clignoter) ; sans passe en route, elle efface — il n'y a rien à
    /// mesurer (jeu non désigné), garder un vieux chiffre mentirait.
    func setSizeMeasureResult(_ sizes: ModsFolderSizes?, again: Bool) {
        if sizes != nil || !again { modsFolderSizes = sizes }
        isMeasuringModsFolder = again
    }

    /// Le poids mesuré suit le renommement d'un dossier : la clé physique
    /// change, le contenu non — **au toggle, pas au prochain scan** (B2-T2).
    /// C'est la clé **physique** (préfixée d'un point pour un mod en pause)
    /// qui sert de clé ici, jamais le nom logique : joindre sur le logique
    /// rendrait 0 octet pour tout mod en pause.
    func renameSizeKey(from oldPhysical: String, to newPhysical: String) {
        modsFolderSizes = modsFolderSizes?.renamingFolder(from: oldPhysical,
                                                          to: newPhysical)
    }
}
