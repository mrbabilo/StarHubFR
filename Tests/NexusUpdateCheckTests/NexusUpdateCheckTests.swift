import Testing
import Foundation
@testable import StarHubTHCore

/// La composition des deux requêtes d'une vérification des mises à jour,
/// extraite du ViewModel (2026-09-11) : le filet Pathoschild part
/// **systématiquement** en parallèle de smapi.io, l'application n'est rendue
/// **qu'une fois les deux résolues** (sinon l'appelant lirait un index
/// Pathoschild vide), et les décisions de fin de passe (succès enregistré,
/// passe incomplète, échec nommé) vivent ici.
struct NexusUpdateCheckTests {

    private let queue = DispatchQueue(label: "test.nexusupdatecheck")

    private static func entry(_ id: String) -> SmapiUpdateRequest.Entry {
        SmapiUpdateRequest.Entry(id: id, updateKeys: [], installedVersion: "1.0.0")
    }

    private static func folder(_ id: String) -> NexusIdLearning.Folder {
        NexusIdLearning.Folder(folderName: id, uniqueId: id, updateKeys: [])
    }

    private static func outcome(mods: Int = 1, completed: Int = 3, total: Int = 3,
                                failure: SmapiUpdateClient.Failure? = nil) -> SmapiUpdateClient.Outcome {
        SmapiUpdateClient.Outcome(mods: (0..<mods).map { SmapiUpdateResponse.Mod(id: "m\($0)") },
                                  batchesCompleted: completed, batchesTotal: total,
                                  failure: failure)
    }

    /// Lance la composition avec des fetchers synchrones et **attend** sa
    /// complétion : la composition revient, les assertions se font dans le
    /// corps du test.
    private func runAndAwait(entries: [SmapiUpdateRequest.Entry] = [Self.entry("a.mod")],
                             folders: [NexusIdLearning.Folder] = [Self.folder("a.mod")],
                             gameVersion: String? = "1.6.15",
                             smapiResult: Result<SmapiUpdateClient.Outcome, SmapiUpdateClient.Failure>? = .success(Self.outcome()),
                             pathoschildFails: Bool = false
    ) async -> NexusUpdateCheck.Composition {
        await withCheckedContinuation { cont in
            NexusUpdateCheck.run(
                entries: entries, folders: folders, gameVersion: gameVersion, queue: queue,
                smapiFetch: { _, _, _, done in
                    if let smapiResult { done(smapiResult) }
                },
                pathoschildFetch: { done in done(pathoschildFails) },
                progress: { _, _ in },
                completion: { cont.resume(returning: $0) })
        }
    }

    // MARK: - La composition

    /// Les deux requêtes résolues : la composition rend le résultat smapi.io,
    /// le parc restitué tel quel, et la passe complète n'a rien à dire.
    @Test func carriesBothResultsOnceBothResolved() async {
        let composition = await runAndAwait(
            entries: [Self.entry("a.mod"), Self.entry("b.mod")],
            folders: [Self.folder("a.mod"), Self.folder("b.mod")])

        #expect(composition.resolution == .applied(isComplete: true))
        #expect(composition.smapiResult != nil)
        #expect(composition.entries.map(\.id) == ["a.mod", "b.mod"])
        #expect(composition.folders.count == 2)
        #expect(composition.checkError == nil)
        #expect(composition.journal.isEmpty)
    }

    /// La version du jeu part **sanitisée** : une valeur qui ne s'analyse pas
    /// (« 1.6.15-beta ») est remplacée par le défaut — sinon smapi.io rend
    /// une liste vide et le lot entier disparaît sans erreur.
    @Test func gameVersionIsSanitizedBeforeSending() async {
        var sent: [String] = []
        let composition = await withCheckedContinuation { (cont: CheckedContinuation<NexusUpdateCheck.Composition, Never>) in
            NexusUpdateCheck.run(
                entries: [Self.entry("a.mod")], folders: [],
                gameVersion: "1.6.15-beta", queue: queue,
                smapiFetch: { _, version, _, done in
                    sent.append(version)
                    done(.success(Self.outcome()))
                },
                pathoschildFetch: { done in done(false) },
                progress: { _, _ in },
                completion: { cont.resume(returning: $0) })
        }
        #expect(composition.resolution == .applied(isComplete: true))
        #expect(sent == [SmapiUpdateRequest.defaultGameVersion])
    }

    /// La progression émise par la requête smapi.io est relayée telle quelle
    /// à la closure de l'appelant.
    @Test func progressIsRelayed() async {
        var seen: [(Int, Int)] = []
        _ = await withCheckedContinuation { (cont: CheckedContinuation<NexusUpdateCheck.Composition, Never>) in
            NexusUpdateCheck.run(
                entries: [Self.entry("a.mod")], folders: [], gameVersion: nil, queue: queue,
                smapiFetch: { _, _, sentProgress, done in
                    sentProgress(2, 7)
                    done(.success(Self.outcome()))
                },
                pathoschildFetch: { done in done(false) },
                progress: { done, total in seen.append((done, total)) },
                completion: { cont.resume(returning: $0) })
        }
        #expect(seen.count == 1)
        #expect(seen[0] == (2, 7))
    }

    /// Une passe **amputée** n'est pas un passage réussi du parc : la cause
    /// se dit, et `isComplete` reste `false` — l'appelant n'enregistrera pas
    /// le succès.
    @Test func incompletePassIsJournaled() async {
        let composition = await runAndAwait(
            smapiResult: .success(Self.outcome(completed: 2, total: 3, failure: .http(503))))

        #expect(composition.resolution == .applied(isComplete: false))
        #expect(composition.checkError == nil)
        #expect(composition.journal.count == 1)
        #expect(composition.journal[0].level == .warning)
        #expect(composition.journal[0].text.contains("2 lot(s) sur 3"))
        #expect(composition.journal[0].text.contains("cause : http(503)"))
    }

    /// Le filet Pathoschild peut échouer sans bloquer l'application smapi.io :
    /// une ligne le dit, la passe continue.
    @Test func pathoschildFailureDoesNotBlockSmapi() async {
        let composition = await runAndAwait(pathoschildFails: true)

        #expect(composition.resolution == .applied(isComplete: true))
        #expect(composition.journal.count == 1)
        #expect(composition.journal[0].text.contains("Dump Pathoschild indisponible"))
    }

    /// smapi.io peut répondre **avant** le dump : la composition n'est rendue
    /// qu'au second — sinon l'appelant lirait un index Pathoschild encore
    /// vide. (Le défaut que le DispatchGroup corrigeait au ViewModel.)
    @Test func smapiAnsweringFirstDoesNotEndTheCompositionEarly() async {
        var smapiDone: ((Result<SmapiUpdateClient.Outcome, SmapiUpdateClient.Failure>) -> Void)? = nil
        var pathoschildDone: ((Bool) -> Void)? = nil
        var completions = 0
        let composition = await withCheckedContinuation { (cont: CheckedContinuation<NexusUpdateCheck.Composition, Never>) in
            NexusUpdateCheck.run(
                entries: [Self.entry("a.mod")], folders: [], gameVersion: nil, queue: queue,
                smapiFetch: { _, _, _, done in smapiDone = done },
                pathoschildFetch: { done in pathoschildDone = done },
                progress: { _, _ in },
                completion: { composition in
                    completions += 1
                    cont.resume(returning: composition)
                })
            // smapi.io répond la première :
            smapiDone?(.success(Self.outcome()))
            // …la composition ne doit pas être partie : on vide la queue pour
            // rendre l'absence **déterministe** — si la complétion avait été
            // enfilée, ce sync l'exécuterait.
            queue.sync { }
            #expect(completions == 0, "la composition est partie avant le dump")
            pathoschildDone?(false)
        }
        #expect(completions == 1)
        #expect(composition.resolution == .applied(isComplete: true))
    }

    /// smapi.io en échec : le 429 est **nommé** (`rate_limited` — l'écran le
    /// dit autrement qu'une interpolation d'enum), les autres erreurs passent
    /// en description brute, et une ligne dit l'échec.
    @Test func failureMapsCheckErrorWithRateLimitedSpecialCase() async {
        let rateLimited = await runAndAwait(smapiResult: .failure(.http(429)))
        guard case .failed = rateLimited.resolution else {
            Issue.record("attendait .failed")
            return
        }
        #expect(rateLimited.checkError == "rate_limited")
        #expect(rateLimited.journal.count == 1)
        #expect(rateLimited.journal[0].text.contains("Vérification des mises à jour en échec"))

        let transport = await runAndAwait(smapiResult: .failure(.transport("réseau indisponible")))
        #expect(transport.checkError == "transport(\"réseau indisponible\")")
    }
}
