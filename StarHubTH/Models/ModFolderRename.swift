import Foundation

/// Renommer le dossier d'un mod — et emmener avec lui tout ce qui s'indexe
/// dessus.
///
/// **Pourquoi ça existe.** `ModItem.id` **est** `folderName`, et c'est la clé
/// de tous les magasins persistés. Deux mods peuvent porter le même nom
/// logique — `X` actif et `.X` en pause sont deux dossiers distincts, et sur le
/// parc de référence ce sont deux `[CP] Seaside Sounds` d'auteurs différents.
/// Ils se partagent alors identité, favori, catégorie, identifiant Nexus,
/// horodatage d'activation et configuration de profil ; un `ForEach` n'en rend
/// qu'un ; et un profil qui demande d'échanger leurs états ne peut pas
/// aboutir — les deux déplacements se refusent l'un l'autre.
///
/// Dénouer cet échange par un nom temporaire aurait rendu le profil applicable
/// **sans rien réparer** : les deux mods auraient continué de partager les
/// quatre magasins que la mesure du 2026-09-05 a trouvés sur le parc réel
/// (`installedModRegistry`, sa sauvegarde, `modActivationTimestamps`,
/// `nexusCustomModIds`). Donner un nom distinct à l'un des deux supprime la
/// cause.
///
/// **Ce que ce type porte** : les règles pures — ce qu'un nom vaut, et comment
/// une clé suit son dossier. Le parcours des douze magasins reste au ViewModel,
/// qui seul les connaît ; il est énuméré à un seul endroit, et cette liste doit
/// rester exhaustive. Et, depuis P5-T9, le déplacement disque que les trois
/// chemins de bascule partagent — écarter le résidu, déplacer, remettre en cas
/// d'échec : du travail fichier injecté d'un `FileManager`, sans une once
/// d'état ni de journalisation, donc testable et (`@MainActor` venu)
/// `nonisolated` sans effort.

/// L'échec d'un renommage de dossier, transporté **à l'appelant**.
///
/// La fonction de renommage est du pur travail disque : elle ne sait pas
/// journaliser, et ne doit pas le savoir — l'appelant (unitaire, bascule en
/// masse, application d'un profil) est le seul à connaître le contexte et le
/// journal. P5-T9 a déplacé ici le message `CRITICAL:` qui vivait dans la
/// fonction : un rollback raté laisse le résidu **nulle part où l'app le
/// retrouve**, ce n'est pas une erreur comme les autres, et chacun des trois
/// appelants le dit à son tour.
///
/// ⚠️ Ne pas confondre avec `ModFolderRenameOutcome` (ViewModel) — qui est
/// le résultat du renommage *demandé par l'utilisateur* dans
/// `ModFolderRenameSection`, un tout autre chemin.
public enum ModFolderRenameFailure: LocalizedError {
    /// Le déplacement lui-même a échoué (et il n'y avait rien à remettre,
    /// ou la remise en place a réussi).
    case moveFailed(Error)
    /// Le déplacement a échoué **et** la remise en place du résidu aussi :
    /// le dossier est resté en `strandedAt`, et l'appelant doit crier.
    case rollbackFailed(original: Error, rollback: Error,
                        strandedAt: String, destination: String)

    /// Le message que les trois appelants affichent. Il est **celui de
    /// l'erreur d'origine** : leurs lignes d'échec ne lisent que
    /// `error.localizedDescription`, et un `enum` nu y afficherait un
    /// « The operation couldn't be completed » sans la moindre cause. Le
    /// détail du rollback, lui, passe par `rollbackCriticalLog` — la ligne
    /// CRITICAL séparée que l'appelant journalise à côté.
    public var errorDescription: String? {
        switch self {
        case .moveFailed(let original):
            return original.localizedDescription
        case .rollbackFailed(let original, _, _, _):
            return original.localizedDescription
        }
    }

    /// La ligne `CRITICAL:` à journaliser quand le rollback a raté — `nil`
    /// sinon. **Une seule définition** : trois copies du même format ont
    /// déjà divergé une fois dans ce dossier (cf. `ModFolderCollision`),
    /// le message ne se recopie pas chez les appelants.
    public var rollbackCriticalLog: String? {
        guard case .rollbackFailed(_, let rollback,
                                   let strandedAt, let destination) = self
        else { return nil }
        return "CRITICAL: toggle rollback failed — mod still in \(strandedAt) "
            + "(could not move back to \(destination): \(rollback))"
    }
}

/// Pourquoi une bascule peut refuser un mod — les trois chemins
/// (unitaire, en masse, application d'un profil) disent la même chose.
///
/// `LocalizedError` parce que le bilan de fin ne lit que
/// `error.localizedDescription` : un `NSError` nu y aurait affiché un code.
/// Le nom du mod et le sens de la bascule sont déjà préfixés par la ligne
/// de journal, la phrase ne les répète pas.
enum FolderToggleRefusal: LocalizedError {
    /// Le dossier de destination appartient à un **autre** mod. Le
    /// déplacer, puis le supprimer, effacerait un mod que l'utilisateur
    /// n'a pas désigné — voir `ModFolderCollision`.
    case folderClaimedByAnotherMod(destination: String, otherUniqueId: String)

    var errorDescription: String? {
        switch self {
        case .folderClaimedByAnotherMod(let destination, let otherUniqueId):
            return "« \(destination) » est déjà le dossier d'un autre mod "
                + "(\(otherUniqueId)). Renommer l'un des deux dossiers pour "
                + "les distinguer."
        }
    }
}

public enum ModFolderRename {

    /// Pourquoi un nom est refusé. Un cas par raison : l'écran doit pouvoir
    /// dire **laquelle**, une phrase générique n'aide personne à corriger.
    public enum Verdict: Equatable, Sendable {
        case ok
        /// Vide, ou fait de blancs.
        case empty
        /// Un point de tête : c'est la marque de pause, pas une lettre du nom.
        case leadingDot
        /// `/` ou `:` — le premier fabrique un composant de pack, le second est
        /// le séparateur historique du Finder.
        case invalidCharacter
        /// Le nom d'un autre dossier. L'accepter recréerait la collision qu'on
        /// répare.
        case alreadyTaken
        /// Le nom actuel : rien à faire, et surtout pas douze migrations de
        /// magasins pour un renommage qui n'en est pas un.
        case unchanged
    }

    /// Le nom retenu : débarrassé de ses blancs de bord.
    public static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ce que vaut `newName` pour le mod dont le nom logique est `current`.
    ///
    /// - Parameter existing: les noms **logiques** de tous les dossiers de
    ///   tête, celui du mod compris.
    public static func validate(_ newName: String,
                                renaming current: String,
                                existing: some Sequence<String>) -> Verdict {
        let name = sanitized(newName)
        guard !name.isEmpty else { return .empty }
        guard !name.hasPrefix(".") else { return .leadingDot }
        guard !name.contains("/"), !name.contains(":") else { return .invalidCharacter }
        // La comparaison ignore la casse : le disque de macOS est insensible à
        // la casse par défaut, donc « seaside » n'ouvre aucune place que
        // « Seaside » n'occupait pas déjà — ni pour le renommage en cours, ni
        // face aux voisins.
        if name.compare(current, options: .caseInsensitive) == .orderedSame {
            return .unchanged
        }
        if existing.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame }) {
            return .alreadyTaken
        }
        return .ok
    }

    /// Le nom **physique** que prend le dossier renommé : l'état de pause est
    /// préservé, et c'est le point de tête qui le porte.
    public static func physicalName(_ logicalName: String, pausedLike currentPhysical: String) -> String {
        (currentPhysical.hasPrefix(".") ? "." : "") + logicalName
    }

    /// Les clés d'un magasin qui suivent un dossier renommé : la sienne, et
    /// celles de ses composants (leur nom logique est le chemin relatif sous
    /// le pack). Un voisin dont le nom *commence* pareil reste — renommer
    /// `Pack` ne touche pas `PackDeLuxe`, la même garde que `ModRemovalPurge`.
    static func movedKeys(in keys: some Sequence<String>, from old: String) -> [String] {
        guard !old.isEmpty else { return [] }
        let componentPrefix = old + "/"
        return keys.filter { $0 == old || $0.hasPrefix(componentPrefix) }
    }

    private static func renamed(_ key: String, from old: String, to new: String) -> String {
        key == old ? new : new + key.dropFirst(old.count)
    }

    /// Ce qu'une clé **partagée** devient quand l'un des deux prétendants se
    /// renomme. Ne s'applique qu'à ce cas : hors collision, une clé suit son
    /// mod, quelle que soit sa nature.
    public enum SharedKeyPolicy: Equatable, Sendable {
        /// Une **préférence** — favori, catégorie, drapeau « sa config suit le
        /// profil », horodatage d'activation. Les deux mods la gardent : la
        /// déplacer ferait perdre au mod resté en place ce qu'elle portait,
        /// pour avoir laissé son voisin se renommer.
        case copy
        /// Une **affirmation sur un mod** — l'identifiant Nexus saisi à la
        /// main, la ligne de registre avec sa date d'installation. Rien ne dit
        /// lequel des deux prétendants elle décrivait. La copier ferait
        /// affirmer au mod renommé quelque chose que personne n'a dit de lui :
        /// il irait chercher ses mises à jour sur la page d'un autre. On la
        /// laisse où elle est — le mod renommé la réapprend de son propre
        /// manifeste au prochain scan.
        case leaveBehind
    }

    /// Fait suivre les clés d'un magasin indexé par nom de dossier.
    ///
    /// - Parameter shared: `true` quand un **autre** mod réclame encore
    ///   l'ancien nom — le cas d'une collision.
    /// - Parameter policy: ce que devient une clé partagée. Ignoré hors
    ///   collision.
    /// - Returns: `true` si quelque chose a bougé. L'appelant ne réécrit le
    ///   disque que dans ce cas.
    @discardableResult
    public static func migrate<Value>(_ store: inout [String: Value],
                                      from old: String, to new: String,
                                      shared: Bool,
                                      policy: SharedKeyPolicy = .copy) -> Bool {
        guard !(shared && policy == .leaveBehind) else { return false }
        let moved = movedKeys(in: store.keys, from: old)
        guard !moved.isEmpty else { return false }
        for key in moved {
            store[renamed(key, from: old, to: new)] = store[key]
            if !shared { store.removeValue(forKey: key) }
        }
        return true
    }

    @discardableResult
    public static func migrate(_ store: inout Set<String>,
                               from old: String, to new: String,
                               shared: Bool,
                               policy: SharedKeyPolicy = .copy) -> Bool {
        guard !(shared && policy == .leaveBehind) else { return false }
        let moved = movedKeys(in: store, from: old)
        guard !moved.isEmpty else { return false }
        for key in moved {
            store.insert(renamed(key, from: old, to: new))
            if !shared { store.remove(key) }
        }
        return true
    }

    // MARK: - Le déplacement disque

    /// Renomme un dossier de mod dans `Mods/`, en traitant le cas où la
    /// destination est déjà occupée.
    ///
    /// La règle vivait en **deux exemplaires** (bascule unitaire, bascule en
    /// masse) et manquait au **troisième** chemin, l'application d'un profil,
    /// qui se contentait d'échouer avec le message brut du système. Les deux
    /// exemplaires divergeaient déjà : l'un préfixait d'un point le dossier
    /// écarté, l'autre non — cf. `ModFolderCollision.asideName`.
    ///
    /// - Throws: `FolderToggleRefusal.folderClaimedByAnotherMod` quand la
    ///   destination appartient à un **autre** mod (le déplacer lui ferait
    ///   perdre favori, note, config de profil et identifiant Nexus, sans un
    ///   mot) ; `ModFolderRenameFailure.moveFailed` quand le déplacement
    ///   échoue ; `ModFolderRenameFailure.rollbackFailed` quand, de surcroît,
    ///   la remise en place du résidu échoue — l'appelant apprend alors où le
    ///   dossier est resté, et c'est **lui** qui journalise le CRITICAL.
    ///   L'erreur du système ne traverse plus cette fonction nue : tout ce
    ///   qu'elle lève est emballé, pour que l'appelant distingue sans
    ///   ambiguïté un refus d'un échec de déplacement.
    public static func moveReplacingStaleDestination(from srcPath: String,
                                                     to dstPath: String,
                                                     destinationName: String,
                                                     uniqueId: String,
                                                     fm: FileManager) throws {
        // Le résidu est **écarté**, pas supprimé : un renommage en échec juste
        // après ne doit pas laisser le mod perdu des deux côtés.
        var aside: String? = nil
        if fm.fileExists(atPath: dstPath) {
            let destinationId = Self.uniqueId(ofModAt: dstPath)
            guard ModFolderCollision.isStaleDuplicate(destinationUniqueId: destinationId,
                                                      toggling: uniqueId) else {
                throw FolderToggleRefusal.folderClaimedByAnotherMod(
                    destination: destinationName,
                    otherUniqueId: destinationId ?? "?")
            }
            let parent = (dstPath as NSString).deletingLastPathComponent
            let leaf = (dstPath as NSString).lastPathComponent
            let asidePath = (parent as NSString)
                .appendingPathComponent(ModFolderCollision.asideName(for: leaf))
            try fm.moveItem(atPath: dstPath, toPath: asidePath)
            aside = asidePath
        }

        do {
            try fm.moveItem(atPath: srcPath, toPath: dstPath)
        } catch {
            // Remettre le résidu en place : sans ça, le mod n'est plus nulle
            // part sous un nom que l'app sache retrouver. Et si la remise
            // échoue elle aussi, l'échec **remonte** : dire où le dossier est
            // resté est une information que seul l'appelant peut porter au
            // journal — la fonction ne sait pas écrire dedans, et c'est
            // voulu (P5-T9).
            if let aside {
                do {
                    try fm.moveItem(atPath: aside, toPath: dstPath)
                } catch let rollbackError {
                    throw ModFolderRenameFailure.rollbackFailed(
                        original: error, rollback: rollbackError,
                        strandedAt: aside, destination: dstPath)
                }
            }
            throw ModFolderRenameFailure.moveFailed(error)
        }

        if let aside { try? fm.removeItem(atPath: aside) }
    }

    /// L'`UniqueID` déclaré par le manifeste d'un dossier de mod, ou `nil`.
    ///
    /// Sert à savoir **à qui appartient** un dossier avant de le déplacer. Passe
    /// par `ManifestJSON`, comme le scan : un manifeste avec commentaires, BOM
    /// ou virgule traînante se lit ici exactement comme là-bas, sinon un mod
    /// bien réel passerait pour un résidu anonyme.
    private static func uniqueId(ofModAt folderPath: String) -> String? {
        let manifestPath = (folderPath as NSString).appendingPathComponent("manifest.json")
        guard let data = FileManager.default.contents(atPath: manifestPath),
              let raw = String(data: data, encoding: .utf8),
              let manifest = ManifestJSON.decode(raw),
              let uniqueId = manifest.caseInsensitiveValue(forKey: "UniqueID") as? String
        else { return nil }
        return uniqueId
    }
}
