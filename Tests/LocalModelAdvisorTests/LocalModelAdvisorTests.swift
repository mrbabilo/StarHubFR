import Foundation
import Testing
@testable import StarHubTHCore

/// Le conseil de modèle local : quel modèle proposer à cette machine, et
/// quand ne rien faire télécharger parce que ce qu'il faut est déjà là.
struct LocalModelAdvisorTests {

    // MARK: - Le palier par mémoire

    @Test func sixteenGigabytesGetsTheMiddleTier() {
        #expect(LocalModelAdvisor.candidate(forRAMGB: 16).tag == "qwen2.5:7b")
    }

    @Test func eightGigabytesGetsTheSmallTier() {
        #expect(LocalModelAdvisor.candidate(forRAMGB: 8).tag == "qwen2.5:3b")
    }

    @Test func thirtyTwoGigabytesGetsTheLargeTier() {
        #expect(LocalModelAdvisor.candidate(forRAMGB: 32).tag == "qwen2.5:14b")
    }

    /// Une machine sous le plancher de la table n'a pas « aucun conseil » :
    /// elle a le plus petit. Rendre `nil` ferait disparaître le bloc d'aide
    /// exactement là où il sert le plus.
    @Test func aMachineBelowTheFloorStillGetsTheSmallestCandidate() {
        #expect(LocalModelAdvisor.candidate(forRAMGB: 4).tag == "qwen2.5:3b")
    }

    /// La table est ordonnée et cohérente : à mémoire croissante,
    /// téléchargement croissant. Un palier mal saisi se verrait ici.
    @Test func theTableIsOrderedByMemoryAndBySize() {
        let candidates = LocalModelAdvisor.candidates
        #expect(candidates.count >= 3)
        #expect(candidates == candidates.sorted { $0.minimumRAMGB < $1.minimumRAMGB })
        #expect(candidates == candidates.sorted { $0.downloadGB < $1.downloadGB })
    }

    // MARK: - Le conseil

    @Test func nothingInstalledAsksForThePullOfTheTier() {
        #expect(LocalModelAdvisor.advise(ramGB: 16, installed: [])
                == .pull(LocalModelAdvisor.candidate(forRAMGB: 16)))
    }

    /// Six Go de téléchargement pour un modèle déjà présent : c'est ce que
    /// le conseil doit éviter.
    @Test func anInstalledSuitableModelIsPreferredOverAnyDownload() {
        #expect(LocalModelAdvisor.advise(ramGB: 16, installed: ["qwen2.5:7b"])
                == .useInstalled("qwen2.5:7b"))
    }

    /// Le tag installé porte souvent un suffixe de quantification. C'est le
    /// même modèle.
    @Test func anInstalledTagWithAQuantizationSuffixStillMatches() {
        #expect(LocalModelAdvisor.advise(ramGB: 16, installed: ["qwen2.5:7b-instruct-q4_K_M"])
                == .useInstalled("qwen2.5:7b-instruct-q4_K_M"))
    }

    /// Le piège : un modèle installé que la machine ne peut pas faire
    /// tourner. Le proposer serait pire que de ne rien dire — l'utilisateur
    /// verrait le serveur ramer ou refuser, sans savoir pourquoi.
    @Test func anInstalledModelTooBigForTheMachineIsNotProposed() {
        #expect(LocalModelAdvisor.advise(ramGB: 8, installed: ["qwen2.5:14b"])
                == .pull(LocalModelAdvisor.candidate(forRAMGB: 8)))
    }

    /// Deux modèles convenables installés : le plus capable que la machine
    /// supporte gagne.
    @Test func theMostCapableInstalledModelTheMachineSupportsWins() {
        #expect(LocalModelAdvisor.advise(ramGB: 16,
                                         installed: ["qwen2.5:3b", "qwen2.5:7b"])
                == .useInstalled("qwen2.5:7b"))
    }

    /// Un modèle installé qu'on ne connaît pas ne se juge pas : on ne sait
    /// ni sa taille ni ce qu'il vaut. Le conseil reste le téléchargement —
    /// le menu du champ Modèle, lui, continue de lister l'existant.
    @Test func anUnknownInstalledModelIsNotJudged() {
        #expect(LocalModelAdvisor.advise(ramGB: 16, installed: ["mistral-small:24b"])
                == .pull(LocalModelAdvisor.candidate(forRAMGB: 16)))
    }

    /// **Le critère qui a manqué.** `qwen3.5:9b` a été conseillé le 2026-08-20 sur
    /// sa seule empreinte mémoire — or il annonce `thinking` et `vision` : il
    /// produit une chaîne de pensée avant de répondre. Mesuré sur un M1 Pro
    /// 16 Go : **plus de 300 secondes** pour « Bonjour ». Pire, le raisonnement
    /// épuise le `max_tokens` du client, qui rejette alors la réponse pour
    /// `finish_reason=length` — chaque clé échouait.
    ///
    /// Aucun modèle à raisonnement ou à vision ne doit entrer dans la table.
    @Test func noCandidateIsAReasoningOrVisionModel() {
        for candidate in LocalModelAdvisor.candidates {
            #expect(!LocalModelAdvisor.reasoningOrVisionFamilies.contains {
                candidate.tag.hasPrefix($0)
            }, "\(candidate.tag) appartient à une famille écartée")
        }
    }

    /// Un modèle installé d'une famille écartée ne doit pas être retenu, même
    /// s'il « rentre » en mémoire : il rentre, et il ne répond pas.
    @Test func anInstalledReasoningModelIsNotProposed() {
        #expect(LocalModelAdvisor.advise(ramGB: 16, installed: ["qwen3.5:9b"])
                == .pull(LocalModelAdvisor.candidate(forRAMGB: 16)))
    }

    // MARK: - La machine

    /// Le seul point impur : la mémoire réelle. On n'en teste que la
    /// vraisemblance — figer une valeur reviendrait à tester le Mac.
    @Test func theMachineReportsAPlausibleAmountOfMemory() {
        #expect(LocalModelAdvisor.machineRAMGB() >= 1)
        #expect(LocalModelAdvisor.machineRAMGB() <= 4096)
    }
}
