import Foundation

/// Un dossier de mod candidat à la mise en pause.
///
/// L'unité est le **dossier de premier niveau**, jamais un mod isolé : un pack
/// multi-mods bascule d'un bloc, et la machinerie de toggle ne trouve que les
/// entrées de premier niveau.
public struct BisectionCandidate: Equatable {
    /// Nom logique du dossier, sans le point de mise en pause.
    public let folderName: String
    /// Identifiants des mods qu'il contient (plusieurs pour un pack).
    public let uniqueIds: [String]
    /// Identifiants dont ce dossier a besoin pour fonctionner.
    public let requires: [String]

    public init(folderName: String, uniqueIds: [String], requires: [String]) {
        self.folderName = folderName
        self.uniqueIds = uniqueIds
        self.requires = requires
    }
}

/// Ce que l'utilisateur constate après une étape.
public enum BisectionOutcome: Equatable {
    case stillBroken
    case fixed
}

public enum BisectionState: Equatable {
    /// On vérifie d'abord que le problème se produit bien avec tout d'actif.
    case reproducing
    case trial(step: Int, total: Int)
    /// Un seul dossier reste : on relance tout sauf lui, pour en avoir le cœur net.
    case confirming(folderName: String)
    case concluded(folderName: String)
    /// La méthode ne peut pas trancher (deux mods fautifs ensemble, par exemple).
    case inconclusive
    /// Le problème ne s'est pas reproduit : rien à chercher.
    case notReproducible
}

/// Recherche du dossier responsable en divisant l'ensemble par deux à chaque
/// étape. Type **pur** : il ne connaît que des noms, ne touche à aucun fichier,
/// et se teste intégralement.
public struct BisectionSession {
    private let ordered: [BisectionCandidate]
    /// Ensemble encore suspect. Se réduit de moitié à chaque étape.
    private var suspects: [BisectionCandidate]
    /// Sous-ensemble effectivement activé à l'étape courante.
    private var currentTrial: [BisectionCandidate] = []
    public private(set) var state: BisectionState

    public init(candidates: [BisectionCandidate]) {
        self.ordered = Self.clustered(candidates)
        self.suspects = self.ordered
        self.state = .reproducing
    }

    /// Dossiers à laisser actifs pour l'étape courante.
    public var foldersToEnable: [String] {
        switch state {
        case .reproducing:
            return ordered.map(\.folderName)
        case .trial:
            return currentTrial.map(\.folderName)
        case .confirming(let suspect):
            return Self.excluding(suspect, from: ordered).map(\.folderName)
        case .concluded, .inconclusive, .notReproducible:
            return ordered.map(\.folderName)
        }
    }

    /// Nombre d'étapes annoncé à l'utilisateur.
    private var totalSteps: Int {
        max(1, Int(ceil(log2(Double(max(ordered.count, 2))))))
    }

    public mutating func record(_ outcome: BisectionOutcome) {
        switch state {
        case .reproducing:
            guard outcome == .stillBroken else { state = .notReproducible; return }
            guard !suspects.isEmpty else { state = .inconclusive; return }
            // Un seul candidat : rien à couper en deux, on passe directement à
            // la vérification. Sans ce court-circuit, l'essai serait l'ensemble
            // suspect entier et la garde de grappe le prendrait pour des mods
            // inséparables — la session conclurait « pas de réponse simple »
            // sur un cas qui a pourtant une réponse. Symétrique du même
            // court-circuit dans la branche `.trial`.
            if suspects.count == 1 {
                state = .confirming(folderName: suspects[0].folderName)
                return
            }
            advance(step: 1)

        case .trial(let step, _):
            // Le problème persiste → le responsable est dans l'essai courant.
            // Il disparaît → il est dans ce qui n'y était pas.
            suspects = outcome == .stillBroken
                ? currentTrial
                : suspects.filter { c in !currentTrial.contains(where: { $0.folderName == c.folderName }) }
            guard !suspects.isEmpty else { state = .inconclusive; return }
            if suspects.count == 1 {
                state = .confirming(folderName: suspects[0].folderName)
                return
            }
            advance(step: step + 1)

        case .confirming(let suspect):
            // Sans lui le problème disparaît : c'est bien lui. Sinon la méthode
            // a atteint sa limite — plusieurs mods fautifs ensemble.
            state = outcome == .fixed ? .concluded(folderName: suspect) : .inconclusive

        case .concluded, .inconclusive, .notReproducible:
            break
        }
    }

    private mutating func advance(step: Int) {
        let half = Array(suspects.prefix((suspects.count + 1) / 2))
        currentTrial = Self.withRequiredDependencies(half, within: ordered)
        // Des mods qui ont besoin les uns des autres forment une grappe que la
        // fermeture reconstitue depuis n'importe quel sous-ensemble : l'essai
        // redevient l'ensemble suspect entier et la recherche n'avance plus.
        // Aucune coupe ne peut les séparer, donc aucun d'eux ne peut être
        // désigné seul — c'est la même réponse que pour deux mods qui ne
        // s'entendent qu'ensemble.
        if Set(currentTrial.map(\.folderName)) == Set(suspects.map(\.folderName)) {
            state = .inconclusive
            return
        }
        // La fermeture vers le haut peut faire *grossir* l'ensemble suspect
        // (un essai ramène les dépendances restées hors de l'ensemble), donc le
        // nombre d'étapes réellement parcourues peut dépasser ⌈log₂(n)⌉.
        // Annoncer « étape 9 sur 7 » ferait mentir la barre de progression :
        // le total annoncé ne descend jamais en dessous de l'étape en cours.
        state = .trial(step: step, total: max(totalSteps, step))
    }

    /// Complète un sous-ensemble avec les dépendances requises, transitivement.
    ///
    /// Utilisé pour construire un essai : un mod doit pouvoir tourner, sinon
    /// l'erreur « dépendance manquante » qu'il remonte imite la panne cherchée.
    /// Fermer dans l'autre sens ici — retirer les orphelins — produisait un
    /// essai vide dès qu'une coupe séparait un mod de sa dépendance, et la
    /// recherche ne convergeait plus.
    static func withRequiredDependencies(_ subset: [BisectionCandidate],
                                         within all: [BisectionCandidate]) -> [BisectionCandidate] {
        var providers: [String: BisectionCandidate] = [:]
        for c in all {
            for id in c.uniqueIds where providers[id] == nil { providers[id] = c }
        }
        var kept = subset
        var present = Set(subset.map(\.folderName))
        var queue = subset
        while let c = queue.popLast() {
            for need in c.requires {
                guard let provider = providers[need],
                      !present.contains(provider.folderName) else { continue }
                present.insert(provider.folderName)
                kept.append(provider)
                queue.append(provider)
            }
        }
        // Conserver l'ordre canonique, pour que les essais restent lisibles.
        return all.filter { present.contains($0.folderName) }
    }

    /// Retire d'un ensemble le dossier donné et tout ce qui en dépend,
    /// transitivement.
    ///
    /// Utilisé pour l'essai de confirmation, où le suspect est délibérément
    /// écarté : ses dépendants ne peuvent pas tourner sans lui, et les laisser
    /// actifs ferait échouer la confirmation pour une raison étrangère au mod
    /// suspecté.
    static func excluding(_ folderName: String,
                          from all: [BisectionCandidate]) -> [BisectionCandidate] {
        var removed = Set([folderName])
        var changed = true
        while changed {
            changed = false
            for c in all where !removed.contains(c.folderName) {
                let missing = c.requires.contains { need in
                    all.contains { removed.contains($0.folderName) && $0.uniqueIds.contains(need) }
                }
                if missing { removed.insert(c.folderName); changed = true }
            }
        }
        return all.filter { !removed.contains($0.folderName) }
    }

    /// Ordonne les candidats pour qu'un dossier suive celui dont il a besoin.
    /// Sans ce tri, une coupe entre un framework et ses dépendants vide un essai
    /// par fermeture et fait perdre une étape.
    static func clustered(_ candidates: [BisectionCandidate]) -> [BisectionCandidate] {
        let providers: [String: String] = candidates.reduce(into: [:]) { acc, c in
            for id in c.uniqueIds { acc[id] = c.folderName }
        }
        var byFolder: [String: BisectionCandidate] = [:]
        for c in candidates { byFolder[c.folderName] = c }

        var visited = Set<String>()
        var out: [BisectionCandidate] = []
        func emit(_ folder: String) {
            guard !visited.contains(folder), let c = byFolder[folder] else { return }
            visited.insert(folder)
            for need in c.requires {
                if let provider = providers[need], provider != folder { emit(provider) }
            }
            out.append(c)
        }
        for c in candidates { emit(c.folderName) }
        return out
    }
}
