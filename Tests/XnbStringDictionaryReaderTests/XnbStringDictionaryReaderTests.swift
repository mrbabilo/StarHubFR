import Foundation
import Testing
@testable import StarHubTHCore

/// Fixtures XNB construites en mémoire — aucune donnée du jeu dans le dépôt.
///
/// Encodage : compteurs de readers/ressources et index de reader en 7-bit,
/// compteur d'entrées et longueurs de chaînes en `u32` LE (layout mesuré du
/// format XNA — le croquis de fixture du plan utilisait du 7-bit partout).
enum XnbFixture {
    static let dictionaryName =
        "Microsoft.Xna.Framework.Content.DictionaryReader`2[[System.String],[System.String]]"
    static let stringReaderName = "Microsoft.Xna.Framework.Content.StringReader"
    static let listName =
        "Microsoft.Xna.Framework.Content.ListReader`1[[System.String]]"

    static func u32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    /// Entier 7-bit, comme l'écrit XNA pour compteurs et index de readers.
    static func vint(_ value: Int) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    /// Chaîne XNA : longueur `u32` LE + UTF-8.
    static func string(_ s: String) -> [UInt8] {
        u32(s.utf8.count) + Array(s.utf8)
    }

    /// Le corps type : readers déclarés, ressources partagées, index racine,
    /// puis les octets d'entrées fournis par l'appelant.
    static func body(readers: [String] = [dictionaryName, stringReaderName],
                     sharedResources: Int = 0,
                     rootIndex: Int = 1,
                     entryBytes: [UInt8]) -> [UInt8] {
        var content: [UInt8] = vint(readers.count)
        for reader in readers {
            content += string(reader)
            content += [0, 0, 0, 0]      // version i32 LE du reader
        }
        content += vint(sharedResources)
        content += vint(rootIndex)
        return content + entryBytes
    }

    /// Paires standard : `u32` count, chaque clé/valeur précédée de l'index
    /// du StringReader (2 quand les readers standard sont déclarés).
    static func standardEntries(_ entries: [(String, String)]) -> [UInt8] {
        var bytes = u32(entries.count)
        for (key, value) in entries {
            bytes += [2] + string(key) + [2] + string(value)
        }
        return bytes
    }

    /// Enveloppe le contenu en fichier XNB non compressé (drapeaux `0x01`).
    static func xnb(version: UInt8 = 5, flags: UInt8 = 0x01,
                    declaredSize: UInt32? = nil, dropLast: Int = 0,
                    content: [UInt8]) -> Data {
        var header: [UInt8] = Array("XNB".utf8) + [UInt8(ascii: "w"), version, flags]
        let size = declaredSize ?? UInt32(10 + content.count)
        header += u32(Int(size))
        var file = header + content
        if dropLast > 0 { file.removeLast(dropLast) }
        return Data(file)
    }

    /// En-tête LZX sans aucun bloc qui suive (`0x81` = HiDef + LZX).
    static func emptyLzx(decompressedSize: UInt32 = 0) -> Data {
        var header: [UInt8] = Array("XNB".utf8) + [UInt8(ascii: "w"), 5, 0x81]
        header += u32(14)                // taille fichier
        header += u32(Int(decompressedSize))
        return Data(header)
    }
}

struct XnbStringDictionaryReaderTests {
    @Test func readsUncompressedDictionary() throws {
        let entries = [("spring", "Spring"), ("Abigail", "Abigail")]
        let file = XnbFixture.xnb(content: XnbFixture.body(
            entryBytes: XnbFixture.standardEntries(entries)))
        #expect(try XnbStringDictionaryReader.read(file)
            == ["spring": "Spring", "Abigail": "Abigail"])
    }

    @Test func rejectsWrongMagic() throws {
        var file = XnbFixture.xnb(content: XnbFixture.body(
            entryBytes: XnbFixture.standardEntries([("a", "b")])))
        file[0] = UInt8(ascii: "A")
        #expect(throws: XnbStringDictionaryReader.ReadError.notXnb) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsOldVersion() {
        let file = XnbFixture.xnb(version: 4, content: XnbFixture.body(
            entryBytes: XnbFixture.standardEntries([("a", "b")])))
        #expect(throws: XnbStringDictionaryReader.ReadError.unsupportedVersion(4)) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsSizeMismatch() {
        let file = XnbFixture.xnb(declaredSize: 999, content: XnbFixture.body(
            entryBytes: XnbFixture.standardEntries([("a", "b")])))
        #expect(throws: XnbStringDictionaryReader.ReadError.sizeMismatch(declared: 999, actual: file.count)) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsLz4() {
        let file = XnbFixture.xnb(flags: 0x40, content: [0])
        #expect(throws: XnbStringDictionaryReader.ReadError.lz4Unsupported) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsSharedResources() {
        let file = XnbFixture.xnb(content: XnbFixture.body(
            sharedResources: 1,
            entryBytes: XnbFixture.standardEntries([("a", "b")])))
        #expect(throws: XnbStringDictionaryReader.ReadError.sharedResourcesUnsupported) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsNonDictionaryRoot() {
        let file = XnbFixture.xnb(content: XnbFixture.body(
            readers: [XnbFixture.listName, XnbFixture.stringReaderName],
            entryBytes: XnbFixture.standardEntries([("a", "b")])))
        #expect(throws: XnbStringDictionaryReader.ReadError
            .rootNotStringDictionary(XnbFixture.listName)) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsMissingStringReader() {
        let file = XnbFixture.xnb(content: XnbFixture.body(
            readers: [XnbFixture.dictionaryName],
            entryBytes: XnbFixture.standardEntries([])))
        #expect(throws: XnbStringDictionaryReader.ReadError.noStringReader) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func truncatedWhenLastByteMissing() {
        let full = XnbFixture.xnb(content: XnbFixture.body(
            entryBytes: XnbFixture.standardEntries([("spring", "Printemps")])))
        // La taille déclarée doit rester cohérente avec l'amputation —
        // sinon sizeMismatch tire avant le parse (et il aurait raison).
        let truncated = XnbFixture.xnb(declaredSize: UInt32(full.count - 1), dropLast: 1,
                                       content: XnbFixture.body(
            entryBytes: XnbFixture.standardEntries([("spring", "Printemps")])))
        #expect(full.count > truncated.count)
        #expect(throws: XnbStringDictionaryReader.ReadError.truncated) {
            _ = try XnbStringDictionaryReader.read(truncated)
        }
    }

    @Test func nullValueIndexReadsAsEmptyString() throws {
        // Index 0 = objet null : clé/valeur vide, sans longueur ni octets.
        let entryBytes = XnbFixture.u32(1) + [2] + XnbFixture.string("key") + [0]
        let file = XnbFixture.xnb(content: XnbFixture.body(entryBytes: entryBytes))
        #expect(try XnbStringDictionaryReader.read(file) == ["key": ""])
    }

    @Test func rejectsForeignReaderIndexInEntries() {
        // Index 3 : pointe un reader qui n'existe pas dans les paires.
        let entryBytes = XnbFixture.u32(1)
            + [3] + XnbFixture.string("key") + [2] + XnbFixture.string("value")
        let file = XnbFixture.xnb(content: XnbFixture.body(entryBytes: entryBytes))
        #expect(throws: XnbStringDictionaryReader.ReadError.entryOverflow) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsSuspiciousEntryCount() {
        let entryBytes = XnbFixture.u32(50_000)   // 500 000 octets attendus, ~0 présents
        let file = XnbFixture.xnb(content: XnbFixture.body(entryBytes: entryBytes))
        #expect(throws: XnbStringDictionaryReader.ReadError.self) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsTooManyTypeReaders() {
        let file = XnbFixture.xnb(content: [65])  // 7-bit : 65 readers déclarés
        #expect(throws: XnbStringDictionaryReader.ReadError.tooManyTypeReaders) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func rejectsOversizedString() {
        let entryBytes = XnbFixture.u32(1) + [2] + XnbFixture.u32(2_000_000)
        let file = XnbFixture.xnb(content: XnbFixture.body(entryBytes: entryBytes))
        #expect(throws: XnbStringDictionaryReader.ReadError.stringTooLong(2_000_000)) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }

    @Test func compressedHeaderMissingWhenNoBlockFollows() {
        let file = XnbFixture.emptyLzx(decompressedSize: 100)
        #expect(throws: XnbStringDictionaryReader.ReadError.compressedHeaderMissing) {
            _ = try XnbStringDictionaryReader.read(file)
        }
    }
}
