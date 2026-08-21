import Foundation
import Testing
@testable import StarHubTHCore

/// L'oracle du service en ligne : le **vrai** DeepL, pas un stub.
///
/// Il existe parce qu'un stub accepte n'importe quel corps. Le 2026-08-21,
/// `ignore_tags` partait en chaîne là où l'API JSON attend un tableau :
/// chaque traduction revenait en `HTTP 400`, toute la suite était verte, et
/// le défaut n'a été vu qu'en interrogeant le service à la main.
///
/// Se skippe proprement sans l'environnement — aucune clé ne vit dans le
/// dépôt, et personne ne doit consommer un quota sans l'avoir voulu :
///
///     DEEPL_API_KEY="…:fx" ./run_tests.sh
///
/// Coût mesuré : une trentaine de caractères du quota mensuel par exécution.
struct DeepLLiveTests {
    static let credentials = ProcessInfo.processInfo.environment["DEEPL_API_KEY"]
        .flatMap(DeepLClient.Credentials.init(key:))

    /// Le quota répond : la clé et l'hôte sont bons.
    @Test(.enabled(if: credentials != nil))
    func theAccountAnswers() async throws {
        let usage = try await DeepLClient.usage(credentials: try #require(Self.credentials),
                                                session: LocalLLMEndpoint.makeSession())
        #expect(usage.limit > 0)
    }

    /// Le corps que ce client construit est **accepté**, et les marques du
    /// jeu traversent le service intactes. C'est le test que la suite stubée
    /// ne peut pas faire.
    @Test(.enabled(if: credentials != nil))
    func aRealTranslationKeepsTheGameMarkers() async throws {
        let outcome = await DeepLClient.translate(
            "Hi {{Name}}, welcome to %farm!",
            context: nil, credentials: try #require(Self.credentials),
            session: LocalLLMEndpoint.makeSession())
        guard case .translated(let french) = outcome else {
            Issue.record("le service a refusé : \(outcome)")
            return
        }
        #expect(french.contains("{{Name}}"))
        #expect(french.contains("%farm"))
        #expect(!french.contains("<x>"))
    }

    /// La forme exacte des voies **par clé** et **par lot** : le contexte y
    /// est l'étiquette de section du fichier i18n, pas une phrase choisie.
    /// `I18nOutline` ne rend jamais d'étiquette vide (`sectionTitle` écarte
    /// le vide et le purement décoratif), mais rien ne borne son contenu —
    /// c'est du commentaire écrit par un moddeur.
    @Test(.enabled(if: credentials != nil))
    func aSectionLabelIsAcceptedAsContext() async throws {
        let outcome = await DeepLClient.translate(
            "Welcome back!", context: "Dialogue — Abigail (heart events 2-6) // ⚠ ne pas traduire les tokens",
            credentials: try #require(Self.credentials),
            session: LocalLLMEndpoint.makeSession())
        guard case .translated(let french) = outcome else {
            Issue.record("le service a refusé : \(outcome)")
            return
        }
        #expect(!french.isEmpty)
    }

    /// Un fragment traduit avec sa phrase en contexte — la voie de la
    /// sélection.
    @Test(.enabled(if: credentials != nil))
    func aFragmentIsTranslatedWithinItsSentence() async throws {
        let outcome = await DeepLClient.translate(
            "deep", context: "Her roots grow very deep here.",
            credentials: try #require(Self.credentials),
            session: LocalLLMEndpoint.makeSession())
        guard case .translated(let french) = outcome else {
            Issue.record("le service a refusé : \(outcome)")
            return
        }
        #expect(!french.isEmpty)
    }
}
