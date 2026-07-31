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
            return ordered.map(\.folderName).filter { $0 != suspect }
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
        currentTrial = Self.closed(half, within: ordered)
        state = .trial(step: step, total: totalSteps)
    }

    /// Retire d'un ensemble tout dossier dont une dépendance requise n'y est
    /// pas, jusqu'à point fixe. Aucun mod ne reste orphelin, donc aucune fausse
    /// erreur « dépendance manquante » ne vient imiter la panne cherchée.
    static func closed(_ subset: [BisectionCandidate],
                       within all: [BisectionCandidate]) -> [BisectionCandidate] {
        // Un besoin satisfait hors candidats (mod non testé, resté actif) ne
        // doit pas exclure : seuls les besoins couverts par un candidat comptent.
        let candidateIds = Set(all.flatMap(\.uniqueIds))
        var kept = subset
        var changed = true
        while changed {
            changed = false
            let present = Set(kept.flatMap(\.uniqueIds))
            let survivors = kept.filter { c in
                c.requires.allSatisfy { !candidateIds.contains($0) || present.contains($0) }
            }
            if survivors.count != kept.count { kept = survivors; changed = true }
        }
        return kept
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
