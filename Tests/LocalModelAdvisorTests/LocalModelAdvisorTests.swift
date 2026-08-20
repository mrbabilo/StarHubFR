import Foundation
import Testing
@testable import StarHubTHCore

/// Le conseil de modèle local : quel modèle proposer à cette machine, et
/// quand ne rien faire télécharger parce que ce qu'il faut est déjà là.
struct LocalModelAdvisorTests {

    // MARK: - Le palier par mémoire

    @Test func sixteenGigabytesGetsTheMiddleTier() {
        #expect(LocalModelAdvisor.candidate(forRAMGB: 16).tag == "qwen3.5:9b")
    }

    @Test func eightGigabytesGetsTheSmallTier() {
        #expect(LocalModelAdvisor.candidate(forRAMGB: 8).tag == "qwen3.5:4b")
    }

    @Test func thirtyTwoGigabytesGetsTheLargeTier() {
        #expect(LocalModelAdvisor.candidate(forRAMGB: 32).tag == "qwen3.5:27b")
    }

    /// Une machine sous le plancher de la table n'a pas « aucun conseil » :
    /// elle a le plus petit. Rendre `nil` ferait disparaître le bloc d'aide
    /// exactement là où il sert le plus.
    @Test func aMachineBelowTheFloorStillGetsTheSmallestCandidate() {
        #expect(LocalModelAdvisor.candidate(forRAMGB: 4).tag == "qwen3.5:4b")
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
        #expect(LocalModelAdvisor.advise(ramGB: 16, installed: ["qwen3.5:9b"])
                == .useInstalled("qwen3.5:9b"))
    }

    /// Le tag installé porte souvent un suffixe de quantification. C'est le
    /// même modèle.
    @Test func anInstalledTagWithAQuantizationSuffixStillMatches() {
        #expect(LocalModelAdvisor.advise(ramGB: 16, installed: ["qwen3.5:9b-instruct-q4_K_M"])
                == .useInstalled("qwen3.5:9b-instruct-q4_K_M"))
    }

    /// Le piège : un modèle installé que la machine ne peut pas faire
    /// tourner. Le proposer serait pire que de ne rien dire — l'utilisateur
    /// verrait le serveur ramer ou refuser, sans savoir pourquoi.
    @Test func anInstalledModelTooBigForTheMachineIsNotProposed() {
        #expect(LocalModelAdvisor.advise(ramGB: 8, installed: ["qwen3.5:27b"])
                == .pull(LocalModelAdvisor.candidate(forRAMGB: 8)))
    }

    /// Deux modèles convenables installés : le plus capable que la machine
    /// supporte gagne.
    @Test func theMostCapableInstalledModelTheMachineSupportsWins() {
        #expect(LocalModelAdvisor.advise(ramGB: 16,
                                         installed: ["qwen3.5:4b", "qwen3.5:9b"])
                == .useInstalled("qwen3.5:9b"))
    }

    /// Un modèle installé qu'on ne connaît pas ne se juge pas : on ne sait
    /// ni sa taille ni ce qu'il vaut. Le conseil reste le téléchargement —
    /// le menu du champ Modèle, lui, continue de lister l'existant.
    @Test func anUnknownInstalledModelIsNotJudged() {
        #expect(LocalModelAdvisor.advise(ramGB: 16, installed: ["mistral-small:24b"])
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
