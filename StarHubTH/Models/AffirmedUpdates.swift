import Foundation

/// Les mods dont l'utilisateur a dit « Je l'ai déjà », et ce que cette
/// affirmation retient.
///
/// Le geste éteint la ligne de mise à jour d'un mod **pour de bon** : l'ancre
/// `.userAffirmed` fige la version envoyée à smapi.io, et
/// `NexusFallbackCheck` compare la page Nexus à cette version-là. Tant que
/// rien ne le montre ni ne l'annule, c'est un aller sans retour — sur
/// l'installation de l'auteur, **34 mods** affirment une version que leur
/// dossier ne porte pas, et plusieurs ressemblent à un clic malheureux
/// (`Florian.TacticalEchoMines` affirmé en 1.3.0 pour un disque en 0.1.0).
///
/// D'où les deux versions côte à côte dans chaque rangée : le numéro affirmé
/// seul ne dit rien, c'est son **écart avec le disque** qui trahit l'erreur.
public enum AffirmedUpdates {

    /// Une ligne de mise à jour **conservée** d'une passe précédente est-elle
    /// encore due ?
    ///
    /// Quand smapi.io ne répond pas pour un mod, sa ligne précédente est
    /// gardée : un mod sans réponse n'est pas un mod à jour. Mais rien ne la
    /// confrontait à ce que l'utilisateur affirme entre-temps, si bien qu'une
    /// ligne posée **avant** l'affirmation survivait indéfiniment — et corriger
    /// la seule recréation n'aurait rien montré à l'écran.
    ///
    /// La comparaison se fait sur la version affirmée quand il y en a une,
    /// exactement comme la reprise Nexus : c'est le même vocabulaire, celui de
    /// l'étiquette de page.
    static func isStillDue(_ update: NexusUpdateChecker.ModUpdate,
                           anchored: String?) -> Bool {
        let installed = SmapiUpdateRequest.comparedVersion(anchored: anchored,
                                                           sent: update.installedVersion)
        return NexusUpdateChecker.isNewer(update.latestVersion, installed: installed)
    }

    /// Un mod installé, réduit à ce que cette liste croise. Même patron que
    /// `SmapiUpdateRequest.Candidate` : le Core ne dépend pas du type
    /// d'affichage de la liste des mods.
    public struct InstalledMod: Equatable, Sendable {
        public let uniqueId: String
        public let name: String
        public let version: String
        /// Le dossier **logique** (jamais préfixé d'un point) : c'est par lui
        /// que `ModFocusResolver` retrouve le mod à coup sûr. Le nom affiché
        /// ne suffit pas — deux mods homonymes existent, et le résolveur
        /// tomberait sur le premier venu.
        public let folderName: String

        public init(uniqueId: String, name: String, version: String, folderName: String) {
            self.uniqueId = uniqueId
            self.name = name
            self.version = version
            self.folderName = folderName
        }
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public var id: String { uniqueId }
        public let uniqueId: String
        public let name: String
        /// La version **affirmée** — celle qu'affichait la ligne au moment du
        /// clic, donc parfois l'étiquette libre d'une page Nexus (« 4 »,
        /// « 1.01 ») plutôt qu'une version SMAPI. Voir
        /// `SmapiUpdateRequest.isExpressibleVersion`.
        public let affirmedVersion: String
        /// Ce que le `manifest.json` déclare aujourd'hui.
        public let manifestVersion: String
        /// Ce qu'il faut passer à `ModFocusResolver` pour ouvrir la fiche.
        public let folderName: String

        /// L'affirmation dit-elle encore autre chose que le disque ?
        ///
        /// `false` quand le manifest a rejoint la version affirmée depuis :
        /// l'ancre ne masque alors plus rien, et la rangée n'a pas à alerter.
        public var disagreesWithDisk: Bool { affirmedVersion != manifestVersion }

        public init(uniqueId: String, name: String,
                    affirmedVersion: String, manifestVersion: String,
                    folderName: String) {
            self.uniqueId = uniqueId
            self.name = name
            self.affirmedVersion = affirmedVersion
            self.manifestVersion = manifestVersion
            self.folderName = folderName
        }
    }

    /// Les affirmations encore vivantes, triées par nom puis identifiant.
    ///
    /// Seules les ancres `.userAffirmed` entrent : une ancre d'installation ou
    /// de constat disque n'est pas un geste de l'utilisateur, il n'y a rien à
    /// lui rendre. Et un mod désinstallé sort — `pruneAnchors` fait ce ménage
    /// au scan, mais la liste ne doit pas dépendre de son passage, sous peine
    /// de proposer de réafficher une ligne qui ne peut plus exister.
    ///
    /// Le tri retombe sur l'`UniqueID` à noms égaux : deux mods homonymes
    /// existent, et sans ce second critère l'ordre suivrait le parcours du
    /// dictionnaire, donc sauterait d'un rendu à l'autre.
    public static func rows(anchors: [String: ModVersionAnchor],
                            installed: [InstalledMod]) -> [Row] {
        let byId = Dictionary(installed.filter { !$0.uniqueId.isEmpty }
                                .map { ($0.uniqueId, $0) },
                              uniquingKeysWith: { first, _ in first })
        return anchors.values
            .filter { $0.origin == .userAffirmed && !$0.uniqueId.isEmpty }
            .compactMap { anchor in
                guard let mod = byId[anchor.uniqueId] else { return nil }
                return Row(uniqueId: anchor.uniqueId, name: mod.name,
                           affirmedVersion: anchor.anchoredVersion,
                           manifestVersion: mod.version,
                           folderName: mod.folderName)
            }
            .sorted {
                $0.name.lowercased() != $1.name.lowercased()
                    ? $0.name.lowercased() < $1.name.lowercased()
                    : $0.uniqueId < $1.uniqueId
            }
    }
}
