import Foundation

// Les erreurs du conteneur sont celles de `XnbStringDictionaryReader.ReadError` :
// le lecteur historique en reste le seul nom public, sa sortie est inchangée.
private typealias ReadError = XnbStringDictionaryReader.ReadError

/// Le conteneur d'un `.xnb` (format XNA, version 5) : en-tête, décompression
/// LZX, liste des readers déclarés et ressources partagées. Commun à tous les
/// lecteurs de contenu typé (`XnbStringDictionaryReader`, `XnbTypedReader`) ;
/// ce type ne sait rien du contenu de l'objet racine.
///
/// Layout : en-tête de 10 octets (`XNB`, plateforme, version, drapeaux,
/// taille totale `u32` LE), puis — après décompression LZX éventuelle — le
/// compte 7-bit des readers, chacun nom + version `u32`, le compte 7-bit des
/// ressources partagées et l'objet racine. Framing LZX : `decompressLZX`.
public enum XnbContainer {
    /// Plafonds hérités de la référence (spec §4).
    private static let maxTypeReaders = 64
    private static let maxDecompressed = 64 << 20      // 64 Mio

    /// Ouvre le fichier. Le curseur rendu est placé **après** le compte des
    /// ressources partagées (refusé s'il n'est pas nul) et **sur** l'index de
    /// reader de l'objet racine, non consommé.
    public static func open(_ data: Data) throws -> (readers: [String], cursor: XnbCursor) {
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

        var cursor = XnbCursor(bytes: content)
        let readerCount = try cursor.vint()
        guard readerCount <= maxTypeReaders else { throw ReadError.tooManyTypeReaders }

        var names: [String] = []
        names.reserveCapacity(readerCount)
        for _ in 0..<readerCount {
            names.append(try cursor.string())
            _ = try cursor.u32LE()     // version du reader — ignorée
        }

        guard try cursor.vint() == 0 else { throw ReadError.sharedResourcesUnsupported }
        return (names, cursor)
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
            guard pos < bytes.count else { throw ReadError.compressedHeaderMissing }
            // Le framing, mesuré sur les fichiers du jeu (Objects.xnb
            // @0xD562 : `ff 48 63 …`) : un bloc **standard** commence par sa
            // taille compressée `u16` BE et décode exactement 0x8000 octets ;
            // le bloc **non standard** — le dernier, dont la sortie ne remplit
            // pas un cadre entier — commence par le marqueur **un octet
            // `0xff`**, puis `frame_size u16` BE et `block_size u16` BE. Il
            // reste compressé : il nourrit le décodeur comme les autres,
            // seule sa taille de sortie change. (Un bloc standard ne peut
            // jamais commencer par 0xff : sa taille compressée est
            // nécessairement inférieure au cadre de 0x8000 octets qu'il
            // produit.)
            if bytes[pos] == 0xFF {
                guard pos + 5 <= bytes.count else { throw ReadError.compressedHeaderMissing }
                let frameSize = Int(bytes[pos + 1]) << 8 | Int(bytes[pos + 2])
                let blockSize = Int(bytes[pos + 3]) << 8 | Int(bytes[pos + 4])
                guard frameSize > 0, blockSize > 0,
                      pos + 5 + blockSize <= bytes.count else {
                    throw ReadError.truncated
                }
                do {
                    out += try decoder.decompressNext(
                        bytes[(pos + 5)..<(pos + 5 + blockSize)][...],
                        outputLength: frameSize)
                } catch let error as LzxdError {
                    throw ReadError.lzxFailed("\(error)")
                }
                pos += 5 + blockSize
            } else {
                guard pos + 2 <= bytes.count else { throw ReadError.compressedHeaderMissing }
                let blockSize = Int(bytes[pos]) << 8 | Int(bytes[pos + 1])
                pos += 2
                guard blockSize > 0, pos + blockSize <= bytes.count else {
                    throw ReadError.truncated
                }
                do {
                    out += try decoder.decompressNext(
                        bytes[pos..<(pos + blockSize)][...],
                        outputLength: LzxdWindowSize.maxChunkSize)
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
}

/// Curseur de lecture sur le contenu décompressé d'un `.xnb`.
public struct XnbCursor {
    /// Plafond d'une chaîne (spec §4).
    private static let maxStringLength = 1 << 20       // 1 Mio

    let bytes: [UInt8]
    var pos = 0

    public init(bytes: [UInt8]) { self.bytes = bytes }

    public var remaining: Int { bytes.count - pos }

    public mutating func byte() throws -> UInt8 {
        guard pos < bytes.count else { throw ReadError.truncated }
        defer { pos += 1 }
        return bytes[pos]
    }

    public mutating func u32LE() throws -> UInt32 {
        var value: UInt32 = 0
        for shift in stride(from: 0, through: 24, by: 8) {
            value |= UInt32(try byte()) << shift
        }
        return value
    }

    public mutating func i32LE() throws -> Int32 {
        Int32(bitPattern: try u32LE())
    }

    public mutating func f32LE() throws -> Float {
        Float(bitPattern: try u32LE())
    }

    public mutating func f64LE() throws -> Double {
        var value: UInt64 = 0
        for shift in stride(from: 0, through: 56, by: 8) {
            value |= UInt64(try byte()) << UInt64(shift)
        }
        return Double(bitPattern: value)
    }

    /// Entier 7-bit encodé, **groupe de poids faible d'abord**
    /// (`BinaryReader.Read7BitEncodedInt`) : continuation sur le bit de
    /// poids fort. L'ordre compte dès 128 — les noms de readers du jeu
    /// dépassent tous ce seuil.
    public mutating func vint() throws -> Int {
        var value = 0
        for group in 0..<5 {   // 5 groupes suffisent pour un Int32
            let byte = try byte()
            value |= Int(byte & 0x7F) << (7 * group)
            if byte & 0x80 == 0 { return value }
        }
        throw ReadError.truncated
    }

    /// Chaîne XNA : longueur **7-bit** + UTF-8 (`BinaryWriter.Write` pour
    /// une `String`). Le plafond précède la vérification de présence :
    /// un compteur fou doit se nommer.
    public mutating func string() throws -> String {
        let length = try vint()
        guard length <= Self.maxStringLength else {
            throw ReadError.stringTooLong(length)
        }
        guard remaining >= length else { throw ReadError.truncated }
        defer { pos += length }
        return String(decoding: bytes[pos..<(pos + length)], as: UTF8.self)
    }
}
