import Foundation

/// Quel modèle local proposer à **cette** machine, et quand ne rien faire
/// télécharger parce que ce qu'il faut est déjà là.
///
/// **Deux** contraintes décident, et la première a coûté cher pour être
/// apprise :
///
/// 1. **Ce que le modèle fait avant de répondre.** Un modèle à *raisonnement*
///    (`thinking`) produit une chaîne de pensée avant sa réponse. Conseillé
///    ici le 2026-08-20, `qwen3.5:9b` a mis **plus de 300 secondes** à
///    répondre « Bonjour » sur un M1 Pro 16 Go — et surtout, son raisonnement
///    épuisait le `max_tokens` de `LocalLLMClient`, qui rejette alors la
///    réponse pour `finish_reason=length` : **chaque clé échouait**. La
///    traduction veut un modèle qui répond, pas un qui délibère. La *vision*
///    est écartée pour une raison plus simple : elle alourdit le modèle sans
///    servir à traduire du texte.
/// 2. **La mémoire.** Un modèle se charge en RAM (unifiée sur Apple Silicon) ;
///    trop gros, il ne rame pas, il fait ramer tout le reste. Les cœurs et le
///    GPU changent la vitesse, pas la faisabilité : on ne s'en sert pas.
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

    /// Les familles écartées : elles délibèrent ou regardent des images, et
    /// aucune des deux ne sert à traduire une ligne de dialogue. La liste
    /// vaut pour la table **et** pour ce qui est déjà installé.
    public static let reasoningOrVisionFamilies = ["qwen3", "deepseek-r1", "llava",
                                                  "gpt-oss", "magistral"]

    /// Trois paliers, mémoire croissante. `qwen2.5` : multilingue, tailles
    /// régulières, **ni raisonnement ni vision**, et explicitement taillé pour
    /// le suivi d'instructions et la sortie structurée. Un palier par classe
    /// de Mac courante (8 Go, 16 Go, 32 Go et au-delà).
    /// Tailles relevées sur ollama.com le 2026-08-20.
    public static let candidates: [Candidate] = [
        Candidate(tag: "qwen2.5:3b", downloadGB: 1.9, minimumRAMGB: 8),
        Candidate(tag: "qwen2.5:7b", downloadGB: 4.7, minimumRAMGB: 12),
        Candidate(tag: "qwen2.5:14b", downloadGB: 9.0, minimumRAMGB: 32),
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
        // Du plus capable au plus modeste : le premier installé gagne. Un
        // modèle d'une famille écartée ne compte pas, même s'il tient en
        // mémoire — il y tient, et il ne répond pas.
        let usable = installed.filter { tag in
            !reasoningOrVisionFamilies.contains { tag.hasPrefix($0) }
        }
        for candidate in affordable.reversed() {
            if let match = usable.first(where: { $0.hasPrefix(candidate.tag) }) {
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
