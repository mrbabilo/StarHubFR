import Foundation

/// Quel modèle local proposer à **cette** machine, et quand ne rien faire
/// télécharger parce que ce qu'il faut est déjà là.
///
/// La contrainte qui décide est la mémoire : un modèle local se charge en
/// RAM (unifiée sur Apple Silicon), et un modèle trop gros pour la machine
/// ne rame pas — il refuse ou fait ramer tout le reste. Le reste (cœurs,
/// GPU) change la vitesse, pas la faisabilité : on ne s'en sert pas.
///
/// La table est **figée dans le code**, comme `LocalLLMClient.knownBricks` :
/// pas d'appel sortant depuis un panneau qui promet que rien ne quitte la
/// machine. Elle est donc à maintenir à la main — tags et tailles relevés
/// sur ollama.com le **2026-08-20**.
///
/// Ce n'est qu'un conseil : le champ Modèle reste libre, et son menu
/// continue de lister ce que le serveur expose, connu de la table ou non.
public enum LocalModelAdvisor {

    /// Un modèle candidat : son tag Ollama, ce qu'il pèse à télécharger, et
    /// la mémoire à partir de laquelle il est raisonnable.
    public struct Candidate: Equatable, Sendable {
        public let tag: String
        /// Taille du téléchargement, en gigaoctets — ce que l'utilisateur
        /// va attendre, pas l'empreinte en mémoire.
        public let downloadGB: Double
        /// La mémoire totale à partir de laquelle ce modèle est proposé.
        public let minimumRAMGB: Int

        public init(tag: String, downloadGB: Double, minimumRAMGB: Int) {
            self.tag = tag
            self.downloadGB = downloadGB
            self.minimumRAMGB = minimumRAMGB
        }
    }

    /// Ce qu'il y a à faire, du point de vue de l'utilisateur.
    public enum Advice: Equatable, Sendable {
        /// Un modèle déjà installé fait l'affaire — le tag est celui que le
        /// serveur annonce, à recopier tel quel dans le champ.
        case useInstalled(String)
        /// Rien d'utilisable : voici celui à télécharger.
        case pull(Candidate)
    }

    /// Trois paliers, mémoire croissante. `qwen3.5` pour sa famille
    /// multilingue et ses tailles régulières ; un palier par classe de Mac
    /// courante (8 Go, 16 Go, 32 Go et au-delà).
    public static let candidates: [Candidate] = [
        Candidate(tag: "qwen3.5:4b", downloadGB: 3.4, minimumRAMGB: 8),
        Candidate(tag: "qwen3.5:9b", downloadGB: 6.6, minimumRAMGB: 12),
        Candidate(tag: "qwen3.5:27b", downloadGB: 17, minimumRAMGB: 32),
    ]

    /// Le plus capable des candidats que cette mémoire supporte. Une machine
    /// sous le plancher de la table reçoit le plus petit plutôt que rien :
    /// rendre `nil` ferait disparaître l'aide là où elle sert le plus.
    public static func candidate(forRAMGB ram: Int) -> Candidate {
        candidates.last { $0.minimumRAMGB <= ram } ?? candidates[0]
    }

    /// Le conseil pour une machine et ce qu'elle a déjà d'installé.
    ///
    /// Un tag installé compte s'il **commence par** le tag d'un candidat :
    /// Ollama suffixe volontiers la quantification (`qwen3.5:9b-instruct-q4_K_M`),
    /// c'est le même modèle. Un modèle inconnu de la table ne se juge pas —
    /// ni sa taille ni ce qu'il vaut ne sont connus.
    public static func advise(ramGB ram: Int, installed: [String]) -> Advice {
        let affordable = candidates.filter { $0.minimumRAMGB <= ram }
        // Du plus capable au plus modeste : le premier installé gagne.
        for candidate in affordable.reversed() {
            if let match = installed.first(where: { $0.hasPrefix(candidate.tag) }) {
                return .useInstalled(match)
            }
        }
        return .pull(candidate(forRAMGB: ram))
    }

    /// La mémoire physique de la machine, en gigaoctets (arrondie à
    /// l'inférieur — 16 Go annoncés en font 16, pas 15). Le seul point impur
    /// du module.
    public static func machineRAMGB() -> Int {
        var bytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &bytes, &size, nil, 0) == 0, bytes > 0 else {
            // Un `sysctl` muet ne doit pas faire disparaître l'aide : le
            // plancher de la table est un défaut prudent.
            return candidates[0].minimumRAMGB
        }
        return Int(bytes / (1024 * 1024 * 1024))
    }
}
