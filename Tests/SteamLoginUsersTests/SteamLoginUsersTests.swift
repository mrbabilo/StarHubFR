import Testing
import Foundation
@testable import StarHubTHCore

/// La boucle VDF de `fetchSteamUser` vivait en ligne dans le ViewModel, sans
/// aucun test. Le vrai `loginusers.vdf` est indenté, multi-comptes, et la
/// lecture historique s'arrête à la première ligne `"MostRecent" "1"` —
/// comportement épinglé tel quel, bizarrerie comprise (voir l'en-tête du
/// type : ne pas « corriger » la règle sans avoir mesuré un vrai fichier).
struct SteamLoginUsersTests {

    /// Forme réelle : deux comptes, indentation par tabulations, le compte
    /// récent en dernier.
    private static let twoAccounts = """
    "users"
    {
        "76561198000000001"
        {
            "PersonaName"      "AncienCompte"
            "MostRecent"       "0"
        }
        "76561198000000002"
        {
            "PersonaName"      "David"
            "MostRecent"       "1"
        }
    }
    """

    @Test func readsTheRecentAccountFromARealisticTwoAccountFile() {
        let parsed = SteamLoginUsers.parse(content: Self.twoAccounts)
        #expect(parsed.steamID == "76561198000000002")
        #expect(parsed.personaName == "David")
    }

    /// Le compte récent en premier : l'arrêt doit tomber sur sa ligne
    /// `"MostRecent" "1"`, avant que le second compte ne soit vu.
    private static let recentAccountFirst = """
    "users"
    {
        "76561198000000009"
        {
            "PersonaName"   "Recent"
            "MostRecent"    "1"
        }
        "76561198000000010"
        {
            "PersonaName"   "JamaisLu"
            "MostRecent"    "0"
        }
    }
    """

    @Test func stopsAtTheFirstMostRecentLine() {
        let parsed = SteamLoginUsers.parse(content: Self.recentAccountFirst)
        #expect(parsed.steamID == "76561198000000009")
        #expect(parsed.personaName == "Recent")
    }

    @Test func aMostRecentZeroLineDoesNotStopTheScan() {
        // Le premier compte est à « 0 » : l'arrêt ne doit pas tomber sur lui.
        let parsed = SteamLoginUsers.parse(content: Self.twoAccounts)
        #expect(parsed.steamID == "76561198000000002")
    }

    @Test func aPersonaNameIsReadUpToItsSecondQuote() {
        // `components(separatedBy: "\"")` rend `parts[3]` : un nom contenant
        // un guillemet est tronqué. Comportement historique épinglé — le VDF
        // réel échappe ces guillemets, le cas reste théorique.
        let parsed = SteamLoginUsers.parse(content: "\"PersonaName\"\t\"Foo \"Bar\"\"")
        #expect(parsed.personaName == "Foo ")
    }

    @Test func anUnreadableOrEmptyFileYieldsEmptyFields() {
        let parsed = SteamLoginUsers.parse(content: "")
        #expect(parsed.steamID == "")
        #expect(parsed.personaName == "")
    }

    /// Un compte sans ligne `MostRecent` (fichier tronqué, premier lancement)
    /// est lu jusqu'au bout.
    @Test func anAccountWithoutMostRecentLineIsStillRead() {
        let content = """
        "users"
        {
            "76561198000000007"
            {
                "PersonaName"   "Cliff"
            }
        }
        """
        let parsed = SteamLoginUsers.parse(content: content)
        #expect(parsed.steamID == "76561198000000007")
        #expect(parsed.personaName == "Cliff")
    }

    /// AGENTS : `\r\n` compte pour une fin de ligne —
    /// `components(separatedBy: .newlines)` laisse des `\r` traînants que le
    /// trim doit retirer. Fixture CRLF permanente.
    @Test func crlfLineEndingsAreTolerated() {
        let content = "\"76561198000000003\"\r\n\"PersonaName\"\t\"Boat\"\r\n\"MostRecent\"\t\"1\"\r\n"
        let parsed = SteamLoginUsers.parse(content: content)
        #expect(parsed.steamID == "76561198000000003")
        #expect(parsed.personaName == "Boat")
    }
}
