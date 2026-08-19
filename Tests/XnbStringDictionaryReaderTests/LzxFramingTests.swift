import Foundation
import Testing
@testable import StarHubTHCore

/// Le framing XMem autour du flux LZX — mesuré sur les fichiers réels du jeu
/// (`Objects.xnb` @0xD562 : `ff 48 63 …`) : le marqueur de bloc non standard
/// est **un octet `0xff`**, suivi de `frame_size u16 BE` puis `block_size
/// u16 BE`, et le bloc reste **compressé** — il nourrit le décodeur comme
/// les autres, seule sa taille de sortie n'est pas 0x8000.
///
/// Ces tests ont été écrits après que les fichiers réels ont tous rendu
/// `.truncated` : l'implémentation lisait le marqueur sur deux octets
/// (`0xFFFF`) et traitait le bloc comme stocké brut.
struct XnbLzxFramingTests {

    // MARK: - Machinerie de fixture (copie locale, chaque cible est son module)

    /// Assemble un flux de bits XMem/LZX : bits MSB-first dans des mots de
    /// 16 bits little-endian — copie du helper des tests du décodeur.
    private struct BitWriter {
        private var bits: [Bool] = []

        mutating func write(_ value: Int, bitCount: Int) {
            for shift in stride(from: bitCount - 1, through: 0, by: -1) {
                bits.append((UInt32(value) >> shift) & 1 == 1)
            }
        }

        mutating func writeRaw(_ bytes: [UInt8]) {
            var i = 0
            while i + 1 < bytes.count {
                write(Int(bytes[i]) | Int(bytes[i + 1]) << 8, bitCount: 16)
                i += 2
            }
            if i < bytes.count {
                write(0, bitCount: 8)
                write(Int(bytes[i]), bitCount: 8)
            }
        }

        func bytes() -> [UInt8] {
            var padded = bits
            while padded.count % 16 != 0 { padded.append(false) }
            var out: [UInt8] = []
            for start in stride(from: 0, to: padded.count, by: 16) {
                var word: UInt16 = 0
                for bit in padded[start..<(start + 16)] { word = (word << 1) | (bit ? 1 : 0) }
                out.append(UInt8(word & 0xFF))
                out.append(UInt8(word >> 8))
            }
            return out
        }
    }

    /// Bloc non compressé (type `0b011`) : en-tête, alignement au mot,
    /// R0/R1/R2, puis les octets bruts. `firstTime` écrit le bit E8 unique
    /// du flux, `false` enchaîne un morceau sur un flux déjà commencé.
    private static func uncompressedChunk(_ content: [UInt8], firstTime: Bool) -> [UInt8] {
        var w = BitWriter()
        if firstTime { w.write(0, bitCount: 1) }   // pas de traduction E8
        w.write(0b011, bitCount: 3)
        w.write(content.count, bitCount: 24)
        let used = (firstTime ? 1 : 0) + 3 + 24
        w.write(0, bitCount: 16 - used % 16)
        for _ in 0..<3 {                           // R0 = R1 = R2 = 1
            w.write(1, bitCount: 16)
            w.write(0, bitCount: 16)
        }
        w.writeRaw(content)
        return w.bytes()
    }

    private static func dictionary(_ entries: [(String, String)]) -> [UInt8] {
        XnbFixture.body(entryBytes: XnbFixture.standardEntries(entries))
    }


    // MARK: - Le framing mesuré

    @Test func readsNonStandardBlockWithSingleByteMarker() throws {
        // Un seul bloc, non standard : 0xff + frame u16 + block u16 + flux.
        let content = Self.dictionary([("spring", "Spring")])
        let chunk = Self.uncompressedChunk(content, firstTime: true)
        var file: [UInt8] = Array("XNB".utf8) + [UInt8(ascii: "w"), 5, 0x81]
        file += XnbFixture.u32(14 + 5 + chunk.count)   // taille fichier
        file += XnbFixture.u32(content.count)          // taille décompressée
        file += [0xFF]
        file += [UInt8(content.count >> 8), UInt8(content.count & 0xFF)]
        file += [UInt8(chunk.count >> 8), UInt8(chunk.count & 0xFF)]
        file += chunk
        let map = try XnbStringDictionaryReader.read(Data(file))
        #expect(map == ["spring": "Spring"])
    }

    @Test func readsStandardBlocksThenNonStandardTail() throws {
        // La forme des vrais fichiers : des blocs standards (u16 BE de taille
        // compressée, sortie 0x8000) puis la queue non standard au marqueur
        // 0xff. Le dictionnaire vit en tête du premier bloc, le reste du
        // contenu est du padding que le parse ignore.
        let head = Self.dictionary([("spring", "Spring"), ("summer", "Summer")])
        let firstContent = head + [UInt8](repeating: 0, count: 32 * 1024 - head.count)
        let tailContent = [UInt8](repeating: 0, count: 100)
        let first = Self.uncompressedChunk(firstContent, firstTime: true)
        let tail = Self.uncompressedChunk(tailContent, firstTime: false)
        var file: [UInt8] = Array("XNB".utf8) + [UInt8(ascii: "w"), 5, 0x81]
        let framing = 2 + first.count + 5 + tail.count
        file += XnbFixture.u32(14 + framing)
        file += XnbFixture.u32(32 * 1024 + tailContent.count)
        file += [UInt8(first.count >> 8), UInt8(first.count & 0xFF)]
        file += first
        file += [0xFF]
        file += [UInt8(tailContent.count >> 8), UInt8(tailContent.count & 0xFF)]
        file += [UInt8(tail.count >> 8), UInt8(tail.count & 0xFF)]
        file += tail
        let map = try XnbStringDictionaryReader.read(Data(file))
        #expect(map == ["spring": "Spring", "summer": "Summer"])
    }
}
