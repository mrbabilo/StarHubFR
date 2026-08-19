import Foundation

/// Tâche 11 du plan P2b — l'endpoint IA locale (spec §6).
///
/// Rien ne doit pouvoir quitter la machine : le prompt transporte le texte
/// des mods, la validation n'accepte donc que le loopback (`localhost`,
/// `127.0.0.0/8` en préfixe d'octets, `::1`), jamais ce qu'un DNS pourrait
/// réécrire (`localhost.evil.com`, `127.0.0.1.nip.io`). La session n'a ni
/// proxy ni redirection suivie.
public enum LocalLLMEndpoint {

    /// Plafond de lecture du corps de réponse — vérifié côté client à la
    /// réception (`LocalLLMClient`).
    public static let maxResponseBytes = 4 * 1024 * 1024

    /// `http://localhost:11434`, `http://127.0.0.1:1234/v1`… Refuse tout
    /// le reste : autre schéma (y compris `https`), tout hôte qui n'est pas
    /// le loopback littéral, toute IP privée ou publique. Rend l'URL telle
    /// quelle (chemin compris) ou `nil`.
    public static func validate(_ baseURL: String) -> URL? {
        guard let url = URL(string: baseURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http",
              let host = url.host else { return nil }
        if host == "localhost" || host == "::1" { return url }
        return isLoopbackIPv4(host) ? url : nil
    }

    /// Session pré-configurée : éphémère, sans proxy, timeout borné, et un
    /// délégué qui **annule** toute redirection HTTP au lieu de la suivre —
    /// un serveur local compromis n'expédie rien vers l'extérieur.
    public static func makeSession(timeout: TimeInterval = 120) -> URLSession {
        makeSession(configuration: .ephemeral, timeout: timeout)
    }

    /// Le point d'injection des tests : même délégué et mêmes règles sur une
    /// configuration fournie (le stub `URLProtocol` s'y installe).
    static func makeSession(configuration: URLSessionConfiguration,
                            timeout: TimeInterval) -> URLSession {
        let config = configuration
        config.connectionProxyDictionary = [:]   // aucun proxy système
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = max(timeout, 300)
        return URLSession(configuration: config,
                          delegate: RedirectCancellingDelegate(),
                          delegateQueue: nil)
    }

    /// `127.0.0.0/8` : première composante `127`, trois octets valides —
    /// comparaison d'octets littéraux, aucune résolution DNS.
    private static func isLoopbackIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.first == "127" else { return false }
        return parts.dropFirst().allSatisfy { part in
            guard (1...3).contains(part.count), part.allSatisfy(\.isNumber),
                  let octet = Int(part), (0...255).contains(octet) else { return false }
            return true
        }
    }

    /// Ne fournit jamais la requête de suivi : la redirection n'est pas
    /// suivie, l'appelant reçoit la réponse 3xx d'origine — que le client
    /// traite en erreur d'endpoint. (Un `task.cancel()` ici serait
    /// non-déterministe : selon la course, la réponse ou l'erreur
    /// `cancelled` arrive ; `nil` est le contrat Apple.)
    private final class RedirectCancellingDelegate: NSObject, URLSessionDataDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
