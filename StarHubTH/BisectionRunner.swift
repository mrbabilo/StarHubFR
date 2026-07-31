import Foundation
import SwiftUI

/// Pilote une recherche : traduit les décisions de `BisectionSession` en
/// déplacements de dossiers, lance le jeu, et attend le retour de l'utilisateur.
///
/// Toute la logique de recherche vit dans `BisectionSession` (Core, testée) ;
/// cette classe ne fait que la relier au disque et à l'interface.
@MainActor
final class BisectionRunner: ObservableObject {
    @Published private(set) var state: BisectionState?
    @Published private(set) var isApplying = false
    /// Candidats de l'essai courant (code-mods seulement), pour l'affichage.
    @Published private(set) var currentFolders: [String] = []
    @Published private(set) var candidateCount = 0
    /// Dossiers déjà mis hors de cause, publiés pour que l'écran puisse montrer
    /// l'avancement réel de la recherche et non seulement un numéro d'étape.
    @Published private(set) var clearedFolders: [String] = []
    @Published private(set) var noCandidates = false
    /// Vrai quand l'utilisateur a répondu sans avoir quitté le jeu. Relancer par
    /// dessus une partie en cours ouvrirait une seconde instance et, pire,
    /// renommerait des dossiers de mods que le jeu tient encore ouverts.
    @Published private(set) var gameStillRunning = false
    /// Mods que le journal met en cause à chaque étape où la panne était encore
    /// là, et jamais quand elle avait disparu. C'est un **second signal**,
    /// indépendant des réponses : la bissection cherche un coupable unique, le
    /// journal, lui, nomme tout ce qui a mal tourné. Les confronter permet de
    /// dire « deux mods sont en cause » là où la recherche seule n'aurait pu
    /// désigner que l'un des deux.
    @Published private(set) var logEvidence: [String] = []

    /// Un relevé par étape : ce que le journal imputait, et si la panne était
    /// encore là.
    private var evidenceLog: [(blamed: Set<String>, stillBroken: Bool)] = []
    @Published var interruptedSnapshot: BisectionSnapshot?

    private var session: BisectionSession?
    private var snapshot: BisectionSnapshot?
    /// Noms des dossiers candidats (code-mods). La recherche ne porte que sur eux.
    private var candidateFolders: Set<String> = []
    /// Mods activés au départ qui ne sont **pas** candidats — packs de contenu,
    /// assets, mods sans code. Toujours laissés actifs pendant la recherche : un
    /// pack de contenu ne fait pas planter le jeu lui-même, mais un code-mod peut
    /// planter en le lisant. Les désactiver empêcherait de reproduire la panne et
    /// contredirait la promesse « tous vos mods, comme aujourd'hui ».
    /// Description de **tous** les mods actifs au départ — candidats compris.
    /// Nécessaire pour savoir ce qui cesse de pouvoir tourner quand un candidat
    /// est mis en pause : un pack de contenu n'est pas candidat, mais il dépend
    /// souvent d'un framework qui l'est.
    private var allEnabled: [BisectionCandidate] = []
    private var nonCandidateFolders: [String] = []

    /// Le runner vit aussi longtemps que le ViewModel (`lazy var bisection`),
    /// donc le cycle de vie est garanti : `unowned` évite un cycle de rétention
    /// sans risquer un accès après libération.
    /// `nonisolated(unsafe)` : référence immuable vers le ViewModel (lui-même non
    /// isolé). Sûr car le runner est `@MainActor` : `vm` n'est lue que depuis le
    /// MainActor. La forme `nonisolated` sûre exigerait un type `Sendable`, ce
    /// qu'une classe mutable comme le ViewModel n'est pas.
    private nonisolated(unsafe) unowned let vm: StarHubTHViewModel

    /// `nonisolated` : l'init ne fait que stocker la référence au ViewModel, il
    /// n'accède à aucun état MainActor. Permet l'instanciation paresseuse depuis
    /// le ViewModel (`lazy var bisection`), lui-même non isolé.
    nonisolated init(vm: StarHubTHViewModel) { self.vm = vm }

    /// Au démarrage de l'app : une recherche laissée en plan ?
    func checkForInterruptedSession() {
        interruptedSnapshot = BisectionSnapshotStore.load()
    }

    func start() {
        guard !isApplying else { return }
        guard !vm.isGameRunning() else { gameStillRunning = true; return }
        gameStillRunning = false
        noCandidates = false
        isApplying = true
        let gameDir = vm.gameDir
        let mods = vm.mods
        // Détection des candidats déportée hors du thread principal : ouvrir un
        // énumérateur de fichiers par dossier de mod (pour chercher un .dll) sur
        // ~900 mods gèlerait l'interface.
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Self.candidates(from: mods, gameDir: gameDir)
            Task { @MainActor [weak self] in self?.continueStart(with: list) }
        }
    }

    private func continueStart(with list: [BisectionCandidate]) {
        guard !list.isEmpty else {
            // Aucun code-mod parmi les mods actifs : rien à mettre en pause.
            isApplying = false
            noCandidates = true
            return
        }

        let enabledFolders = vm.mods.filter(\.isEnabled).map(\.folderName)
        // L'instantané part sur le disque AVANT le premier déplacement.
        let snap = BisectionSnapshot(enabledFolders: enabledFolders, startedAt: Date())
        BisectionSnapshotStore.save(snap)
        snapshot = snap

        candidateFolders = Set(list.map(\.folderName))
        candidateCount = list.count
        nonCandidateFolders = enabledFolders.filter { !candidateFolders.contains($0) }
        allEnabled = Self.describe(vm.mods.filter(\.isEnabled))

        let s = BisectionSession(candidates: list)
        session = s
        state = s.state
        clearedFolders = s.clearedFolders
        apply(s.foldersToEnable) { [weak self] _ in self?.launch() }
    }

    /// Lance le jeu pour une étape de la recherche.
    ///
    /// `honoringCloseAfterLaunch: false` : le réglage « quitter StarHubFR après
    /// le lancement » ferait quitter l'application à *chaque* étape, en laissant
    /// la modlist à moitié en pause et sans personne pour recueillir la réponse.
    /// Le réglage garde tout son effet pour le bouton de l'accueil.
    private func launch() {
        vm.launchGame(honoringCloseAfterLaunch: false)
    }

    func answer(_ outcome: BisectionOutcome) {
        guard !isApplying, var s = session else { return }
        // Le jeu doit être fermé avant l'étape suivante : les dossiers de mods
        // vont être renommés, et le jeu les tient ouverts tant qu'il tourne.
        guard !vm.isGameRunning() else { gameStillRunning = true; return }
        gameStillRunning = false
        // Le journal a été réécrit par la partie qui vient de finir : le relire
        // maintenant, sinon on jugerait sur la session précédente.
        vm.loadSmapiLog { [weak self] in
            self?.recordLogEvidence(stillBroken: outcome == .stillBroken)
        }
        s.record(outcome)
        session = s
        state = s.state
        clearedFolders = s.clearedFolders
        switch s.state {
        case .concluded, .inconclusive, .notReproducible:
            // Recherche finie : on remet tout comme avant, sauf le mod trouvé
            // (s'il y en a un), laissé en pause pour que l'utilisateur décide.
            let keepPaused = s.state.concludedFolder.map { [$0] } ?? []
            let restore = (snapshot?.enabledFolders ?? []).filter { !keepPaused.contains($0) }
            // On n'efface que l'instantané sur disque (ne pas re-proposer une
            // reprise au prochain démarrage) : l'instantané mémoire reste, car le
            // bouton « Tout remettre » de la carte finale s'appuie dessus pour
            // restaurer y compris le coupable. `restoreAndStop` le vide ensuite.
            // Et seulement si tout a bougé : un dossier resté en pause rend
            // l'instantané indispensable, on le garde pour le prochain démarrage.
            apply(restore) { BisectionSnapshotStore.finish($0) }
        default:
            apply(s.foldersToEnable) { [weak self] _ in self?.launch() }
        }
    }

    /// Relève ce que le journal impute à cette étape, et recalcule les mods
    /// systématiquement présents dans les échecs et absents des réussites.
    private func recordLogEvidence(stillBroken: Bool) {
        let blamed = Set((vm.smapiDiagnostics?.topErrorMods.map(\.name) ?? [])
                         + (vm.smapiDiagnostics?.failed.map(\.name) ?? []))
        evidenceLog.append((blamed: blamed, stillBroken: stillBroken))

        let failures = evidenceLog.filter(\.stillBroken).map(\.blamed)
        let successes = evidenceLog.filter { !$0.stillBroken }.map(\.blamed)
        guard let first = failures.first else { logEvidence = []; return }
        // Présent dans TOUS les échecs…
        var common = failures.dropFirst().reduce(first) { $0.intersection($1) }
        // …et dans AUCUNE réussite : un mod qui se plaint aussi quand tout va
        // bien ne dit rien de la panne.
        for ok in successes { common.subtract(ok) }
        logEvidence = common.sorted()
    }

    func restoreAndStop() {
        guard !isApplying else { return }
        let restore = snapshot?.enabledFolders ?? interruptedSnapshot?.enabledFolders ?? []
        // Rien à restaurer (recherche n'ayant rien déplacé — ex. zéro candidat,
        // ou déjà restauré) : on se contente de réinitialiser l'état, SANS
        // appeler applyEnabledFolders([]) qui désactiverait tous les mods.
        guard !restore.isEmpty else { reset(); return }
        apply(restore) { [weak self] outcome in
            guard let self else { return }
            // Disque et mémoire sont conditionnés à la **même** réponse : ils ne
            // peuvent pas diverger.
            guard BisectionSnapshotStore.finish(outcome) else {
                // Un dossier n'a pas pu être remis en place : l'instantané reste,
                // sur disque *et* en mémoire, pour que la remise en état soit
                // réessayable une fois l'obstacle levé (Finder refermé, jumeau
                // « .Nom » retiré) — au prochain démarrage s'il le faut.
                // Mais la recherche, elle, s'arrête là : les dossiers sur disque
                // ne sont plus ceux de l'étape en cours. Laisser l'étape à
                // l'écran laisserait ses boutons de réponse actifs, et un verdict
                // rendu sur cet état ferait converger la recherche sur un
                // innocent. On repasse donc sur l'écran « recherche
                // interrompue » — carte du Diagnostic et bandeau de l'accueil —
                // qui ne propose plus qu'une chose : réessayer.
                // Surtout pas `reset()` : il efface l'instantané.
                self.interruptedSnapshot = self.snapshot ?? self.interruptedSnapshot
                self.session = nil
                self.state = nil
                return
            }
            self.reset()
            // Une remise en état silencieuse laisse un doute : le dire.
            self.vm.showModal(message: self.vm.L(L10n.Bisect.restored))
        }
    }

    private func reset() {
        BisectionSnapshotStore.clear()
        snapshot = nil
        interruptedSnapshot = nil
        session = nil
        state = nil
        noCandidates = false
    }

    /// Applique un essai : active les code-mods donnés par le modèle **plus**
    /// tous les mods non candidats (contenu), met en pause les autres candidats.
    /// `trialFolders` est publié dans `currentFolders` pour l'affichage (l'essai,
    /// pas le bruit des content mods).
    /// `next` reçoit le résultat de l'application : les étapes s'en moquent (le
    /// jeu se lance quand même, et l'alerte a déjà prévenu), mais les remises en
    /// état en dépendent — voir `restoreAndStop`.
    private func apply(_ trialFolders: [String],
                       then next: @escaping (BisectionRestoreOutcome) -> Void) {
        isApplying = true
        currentFolders = trialFolders
        // Les mods hors périmètre ne sont pas activés aveuglément : un pack de
        // contenu dont le framework est en pause ne peut pas tourner, et le
        // laisser actif faisait écarter dix-neuf packs d'un coup par SMAPI —
        // le jeu changeait pour une raison étrangère au mod cherché.
        let kept = Set(trialFolders).union(nonCandidateFolders)
        let applied = BisectionSession.runnable(allEnabled.filter { kept.contains($0.folderName) },
                                                knowing: allEnabled).map(\.folderName)
        vm.applyEnabledFolders(applied) { [weak self] outcome in
            self?.isApplying = false
            next(outcome)
        }
    }

    /// Décrit des mods sous la forme attendue par la fermeture de dépendances.
    /// Sans filtre sur le code : on veut aussi les packs de contenu, car ce sont
    /// eux qui cessent de pouvoir tourner quand leur framework part en pause.
    private nonisolated static func describe(_ mods: [ModItem]) -> [BisectionCandidate] {
        mods.map { mod in
            let children = mod.isGroup ? (mod.children ?? []) : [mod]
            return BisectionCandidate(
                folderName: mod.folderName,
                uniqueIds: children.map(\.uniqueId).filter { !$0.isEmpty },
                requires: children.flatMap(\.dependencies).filter(\.isRequired).map(\.uniqueId)
            )
        }
    }

    /// Candidats = dossiers de premier niveau actifs contenant du code.
    /// Un pack compte pour un, puisqu'il bascule d'un bloc. Statique : ne dépend
    /// d'aucun état d'instance, donc exécutable hors du thread principal.
    /// Statique et `nonisolated` : ne dépend d'aucun état d'instance ni du
    /// MainActor, donc exécutable hors du thread principal (détection des
    /// candidats déportée depuis `start`).
    private nonisolated static func candidates(from mods: [ModItem], gameDir: String) -> [BisectionCandidate] {
        let modsPath = (gameDir as NSString).appendingPathComponent("Mods")
        return mods.compactMap { mod -> BisectionCandidate? in
            guard mod.isEnabled else { return nil }
            let folder = (modsPath as NSString).appendingPathComponent(mod.physicalFolderName)
            guard containsCode(at: folder) else { return nil }
            let children = mod.isGroup ? (mod.children ?? []) : [mod]
            return BisectionCandidate(
                folderName: mod.folderName,
                uniqueIds: children.map(\.uniqueId).filter { !$0.isEmpty },
                requires: children.flatMap(\.dependencies).filter(\.isRequired).map(\.uniqueId)
            )
        }
    }

    /// Un dossier « contient du code » s'il embarque un `.dll` : un pack de
    /// contenu ne s'exécute pas, il est lu par Content Patcher.
    private nonisolated static func containsCode(at path: String) -> Bool {
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return false }
        for case let file as String in enumerator where file.lowercased().hasSuffix(".dll") {
            return true
        }
        return false
    }
}

private extension BisectionState {
    var concludedFolder: String? {
        if case .concluded(let folder) = self { return folder }
        return nil
    }
}
