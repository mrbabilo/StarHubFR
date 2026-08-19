import Foundation

/// Un `.xnb` dictionnaire `string → string` → `[String: String]` — rien
/// d'autre. Volontairement étroit, comme le lecteur de la référence : ce
/// n'est pas un parseur XNB général, c'est ce qu'il faut pour lire les
/// assets de localisation du jeu (`Content/Strings/*.xnb`, dictionnaires
/// `DictionaryReader` String→String, compressés LZX — mesuré : 373/373).
///
/// Layout (mesuré sur les fichiers du jeu + `xnb.rs` de la référence,
/// spec P2b §4) : magie `XNB`, plateforme, version 5, drapeaux, taille
/// fichier `u32` LE à l'offset 6. LZX (`0x80`) : taille décompressée `u32`
/// LE à l'offset 10 puis le framing de blocs. Non compressé : contenu à
/// l'offset 10. LZ4 (`0x40`) : refusé — le jeu ne l'utilise jamais.
///
/// Encodage du contenu : compteurs de readers, ressources partagées et
/// index de reader en **7-bit** ; compteur d'entrées et longueurs de
/// chaînes en **`u32` LE** (le format XNA — pas du 7-bit partout).
///
/// Framing LZX : blocs de `0x8000` octets décompressés. Chaque bloc :
/// `u16` BE de taille compressée ; si `0xFFFF`, le bloc est stocké brut —
/// `frame_size u16` BE + `block_size u16` BE puis les octets tels quels
/// (la compression aurait grossi le texte) ; sinon les `block_size` octets
/// nourrissent `LzxdDecoder.decompressNext`.
///
/// Toute dérive est une **erreur nommée** — jamais un dictionnaire
/// silencieusement vide (spec §8.5).
public enum XnbStringDictionaryReader {
    public enum ReadError: Error, Equatable, Sendable {
        case notXnb
        case unsupportedVersion(UInt8)
        case sizeMismatch(declared: UInt32, actual: Int)
        case lz4Unsupported
        case lzxUnsupported
        case compressedHeaderMissing
        case tooManyTypeReaders
        case sharedResourcesUnsupported
        case rootNotStringDictionary(String)
        case noStringReader
        case entryCountSuspicious(count: UInt32, remaining: Int)
        case stringTooLong(Int)
        case entryOverflow
        /// Le flux LZX est indécodable (ou prétend une taille décompressée
        /// déraisonnable) — ajouté au-delà du plan : l'échec du décodeur
        /// mérite son nom, pas un `truncated` mensonger.
        case lzxFailed(String)
        case truncated
    }

    private static let dictionaryReaderName =
        "Microsoft.Xna.Framework.Content.DictionaryReader`2[[System.String],[System.String]]"
    private static let stringReaderName =
        "Microsoft.Xna.Framework.Content.StringReader"

    /// Plafonds hérités de la référence (spec §4).
    private static let maxTypeReaders = 64
    private static let maxEntries: UInt32 = 250_000
    private static let maxStringLength = 1 << 20       // 1 Mio
    private static let maxDecompressed = 64 << 20      // 64 Mio

    public static func read(_ data: Data) throws -> [String: String] {
        let bytes = [UInt8](data)

        // En-tête : magie, plateforme (ignorée), version, drapeaux, taille.
        guard bytes.count >= 10,
              bytes[0] == UInt8(ascii: "X"), bytes[1] == UInt8(ascii: "N"),
              bytes[2] == UInt8(ascii: "B") else { throw ReadError.notXnb }

        let version = bytes[4]
        guard version == 5 else { throw ReadError.unsupportedVersion(version) }

        let declaredSize = UInt32(bytes[6]) | UInt32(bytes[7]) << 8
            | UInt32(bytes[8]) << 16 | UInt32(bytes[9]) << 24
        guard declaredSize == bytes.count else {
            throw ReadError.sizeMismatch(declared: declaredSize, actual: bytes.count)
        }

        let flags = bytes[5]
        let content: [UInt8]
        if flags & 0x80 != 0 {
            content = try decompressLZX(bytes)
        } else if flags & 0x40 != 0 {
            throw ReadError.lz4Unsupported
        } else {
            content = Array(bytes[10...])
        }

        return try parseDictionary(content)
    }

    // MARK: - Framing LZX

    private static func decompressLZX(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count >= 14 else { throw ReadError.compressedHeaderMissing }
        let target = Int(UInt32(bytes[10]) | UInt32(bytes[11]) << 8
            | UInt32(bytes[12]) << 16 | UInt32(bytes[13]) << 24)
        guard target > 0, target <= maxDecompressed else {
            throw ReadError.lzxFailed("taille décompressée invalide (\(target))")
        }

        var out = [UInt8]()
        out.reserveCapacity(target)
        var decoder = LzxdDecoder(window: .kb64)
        var pos = 14

        while out.count < target {
            guard pos + 2 <= bytes.count else { throw ReadError.compressedHeaderMissing }
            let blockSize = Int(bytes[pos]) << 8 | Int(bytes[pos + 1])

            if blockSize == 0xFFFF {
                // Bloc stocké brut : la compression aurait grossi le texte.
                guard pos + 6 <= bytes.count else { throw ReadError.compressedHeaderMissing }
                let frameSize = Int(bytes[pos + 2]) << 8 | Int(bytes[pos + 3])
                let rawSize = Int(bytes[pos + 4]) << 8 | Int(bytes[pos + 5])
                guard frameSize > 0, rawSize > 0,
                      pos + 6 + rawSize <= bytes.count else {
                    throw ReadError.truncated
                }
                out += bytes[(pos + 6)..<(pos + 6 + rawSize)]
                pos += 6 + rawSize
            } else {
                pos += 2
                guard blockSize > 0, pos + blockSize <= bytes.count else {
                    throw ReadError.truncated
                }
                let frame = min(LzxdWindowSize.maxChunkSize, target - out.count)
                do {
                    let decoded = try decoder.decompressNext(
                        bytes[pos..<(pos + blockSize)][...], outputLength: frame)
                    out += decoded
                } catch let error as LzxdError {
                    throw ReadError.lzxFailed("\(error)")
                }
                pos += blockSize
            }
        }

        guard out.count == target else {
            throw ReadError.lzxFailed("le framing a produit \(out.count) octets au lieu de \(target)")
        }
        return out
    }

    // MARK: - Contenu typé

    private static func parseDictionary(_ content: [UInt8]) throws -> [String: String] {
        var cursor = Cursor(bytes: content)

        let readerCount = try cursor.vint()
        guard readerCount <= maxTypeReaders else { throw ReadError.tooManyTypeReaders }

        var names: [String] = []
        names.reserveCapacity(readerCount)
        for _ in 0..<readerCount {
            names.append(try cursor.string())
            _ = try cursor.u32LE()     // version du reader — ignorée
        }

        guard try cursor.vint() == 0 else { throw ReadError.sharedResourcesUnsupported }

        let rootIndex = try cursor.vint()
        guard rootIndex >= 1, rootIndex <= readerCount else { throw ReadError.entryOverflow }
        guard names[rootIndex - 1] == dictionaryReaderName else {
            throw ReadError.rootNotStringDictionary(names[rootIndex - 1])
        }

        guard let stringReaderSlot = names.firstIndex(of: stringReaderName) else {
            throw ReadError.noStringReader
        }
        let stringReaderIndex = stringReaderSlot + 1   // les index sont 1-based

        let entryCount = try cursor.u32LE()
        // Un compteur fou doit se nommer avant la boucle : au-delà du
        // plafond, ou des entrées déclarées alors qu'il ne reste aucun
        // octet (une paire en exige au moins deux). Une entrée unique à
        // longue chaîne reste légitime — pas d'heuristique de taille.
        if entryCount > maxEntries || (entryCount > 0 && cursor.remaining == 0) {
            throw ReadError.entryCountSuspicious(count: entryCount, remaining: cursor.remaining)
        }

        var dictionary = [String: String]()
        dictionary.reserveCapacity(Int(entryCount))
        for _ in 0..<entryCount {
            let key = try entryString(&cursor, stringReaderIndex: stringReaderIndex)
            let value = try entryString(&cursor, stringReaderIndex: stringReaderIndex)
            dictionary[key] = value
        }
        return dictionary
    }

    /// Une chaîne de paire : index de reader 7-bit (0 = null → vide, sinon
    /// forcément le StringReader), puis la chaîne.
    private static func entryString(
        _ cursor: inout Cursor, stringReaderIndex: Int
    ) throws -> String {
        let index = try cursor.vint()
        guard index == 0 || index == stringReaderIndex else { throw ReadError.entryOverflow }
        return index == 0 ? "" : try cursor.string()
    }

    // MARK: - Curseur de lecture

    private struct Cursor {
        let bytes: [UInt8]
        var pos = 0

        var remaining: Int { bytes.count - pos }

        mutating func byte() throws -> UInt8 {
            guard pos < bytes.count else { throw ReadError.truncated }
            defer { pos += 1 }
            return bytes[pos]
        }

        mutating func u32LE() throws -> UInt32 {
            var value: UInt32 = 0
            for shift in stride(from: 0, through: 24, by: 8) {
                value |= UInt32(try byte()) << shift
            }
            return value
        }

        /// Entier 7-bit encodé (continuation sur le bit de poids fort).
        mutating func vint() throws -> Int {
            var value = 0
            for _ in 0..<5 {   // 5 octets suffisent pour un Int32
                let byte = try byte()
                value = (value << 7) | Int(byte & 0x7F)
                if byte & 0x80 == 0 { return value }
            }
            throw ReadError.truncated
        }

        /// Chaîne XNA : longueur `u32` LE + UTF-8. Le plafond précède la
        /// vérification de présence : un compteur fou doit se nommer.
        mutating func string() throws -> String {
            let length = Int(try u32LE())
            guard length <= maxStringLength else { throw ReadError.stringTooLong(length) }
            guard remaining >= length else { throw ReadError.truncated }
            defer { pos += length }
            return String(decoding: bytes[pos..<(pos + length)], as: UTF8.self)
        }
    }
}
