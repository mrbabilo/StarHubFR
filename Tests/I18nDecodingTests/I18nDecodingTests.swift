import Testing
import Foundation
@testable import StarHubTHCore

/// Lire un fichier i18n comme SMAPI le lit.
///
/// SMAPI appelle `File.ReadAllText`, qui honore la marque d'ordre des octets
/// puis se rabat sur UTF-8 **en remplaçant** les octets invalides — sans jamais
/// échouer. Vérifié en exécutant ce chemin sur la DLL du jeu.
///
/// Notre lecture s'arrêtait à `String(data:encoding:.utf8)`, qui rend `nil` au
/// premier octet fautif. Quatre fichiers du parc en faisaient les frais : un
/// `ru.json` en UTF-16 LE que le jeu lit parfaitement, et trois `es.json` dans
/// un jeu 8 bits hérité qu'il charge avec les accents remplacés.
struct I18nFileDecoderTests {
    @Test func plainUtf8IsReadAsIs() throws {
        let decoded = try #require(I18nFileDecoder.decode(Data(#"{"a": "été"}"#.utf8)))
        #expect(decoded.text == #"{"a": "été"}"#)
        #expect(decoded.hasReplacedBytes == false)
    }

    @Test func aUtf8ByteOrderMarkIsConsumed() throws {
        // La marque ne doit pas rester dans le texte : `JSONSerialization` la
        // refuserait alors que le fichier est parfaitement valide.
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(#"{"a": "1"}"#.utf8))
        let decoded = try #require(I18nFileDecoder.decode(data))
        #expect(decoded.text == #"{"a": "1"}"#)
        #expect(decoded.hasReplacedBytes == false)
    }

    @Test func utf16LittleEndianIsReadPerfectly() throws {
        // Cas réel : `DestroyableBushes/i18n/ru.json`. SMAPI le lit sans perdre
        // un caractère — nous le refusions entièrement.
        let source = #"{"a": "Минимальное"}"#
        var data = Data([0xFF, 0xFE])
        for unit in Array(source.utf16) {
            data.append(UInt8(unit & 0xFF))
            data.append(UInt8(unit >> 8))
        }
        let decoded = try #require(I18nFileDecoder.decode(data))
        #expect(decoded.text == source)
        #expect(decoded.hasReplacedBytes == false)
    }

    @Test func utf16BigEndianIsReadToo() throws {
        let source = #"{"a": "1"}"#
        var data = Data([0xFE, 0xFF])
        for unit in Array(source.utf16) {
            data.append(UInt8(unit >> 8))
            data.append(UInt8(unit & 0xFF))
        }
        let decoded = try #require(I18nFileDecoder.decode(data))
        #expect(decoded.text == source)
    }

    @Test func legacyBytesAreReplacedRatherThanRefused() throws {
        // Cas réel : trois `es.json` du parc. `0xE9` seul est un « é » en
        // Latin-1, pas une séquence UTF-8 valide. SMAPI ne s'arrête pas pour
        // autant : il substitue et charge le fichier, accents en moins.
        var data = Data(#"{"a": "a"#.utf8)
        data.append(0xE9)
        data.append(Data(#"t"}"#.utf8))
        let decoded = try #require(I18nFileDecoder.decode(data))
        #expect(decoded.hasReplacedBytes)
        // Le JSON reste structurellement lisible — c'est tout l'enjeu.
        #expect(decoded.text.contains("\"a\""))
        #expect(decoded.text.hasSuffix("\"}"))
    }

    @Test func anEmptyFileDecodesToNothing() throws {
        let decoded = try #require(I18nFileDecoder.decode(Data()))
        #expect(decoded.text.isEmpty)
    }

    @Test func aBareByteOrderMarkYieldsEmptyText() throws {
        let decoded = try #require(I18nFileDecoder.decode(Data([0xEF, 0xBB, 0xBF])))
        #expect(decoded.text.isEmpty)
    }
}

/// Le parseur laxiste doit accepter des octets, pas seulement une `String` déjà
/// décodée : c'est là que se jouait le refus des quatre fichiers.
struct I18nParserDataTests {
    @Test func parsesUtf16Data() throws {
        let source = #"{"a": "Минимальное"}"#
        var data = Data([0xFF, 0xFE])
        for unit in Array(source.utf16) {
            data.append(UInt8(unit & 0xFF))
            data.append(UInt8(unit >> 8))
        }
        let parsed = try #require(try? I18nLenientParser.parse(data))
        #expect(parsed["a"] == "Минимальное")
    }

    @Test func parsesLegacyBytesWithReplacement() throws {
        var data = Data(#"{"a": "caf"#.utf8)
        data.append(0xE9)
        data.append(Data(#""}"#.utf8))
        let parsed = try #require(try? I18nLenientParser.parse(data))
        // La clé et la structure survivent ; seul l'accent est perdu, comme
        // dans le jeu.
        #expect(parsed["a"]?.hasPrefix("caf") == true)
    }
}
