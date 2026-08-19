import Testing
@testable import StarHubTHCore

/// Assemble un flux de bits XMem/LZX : bits MSB-first dans des mots de
/// 16 bits little-endian, mots complets seulement (copie locale du helper
/// des tests d'arbres — chaque cible de test est son propre module).
private struct LzxdBitWriter {
    private var bits: [Bool] = []

    mutating func write(_ value: Int, bitCount: Int) {
        for shift in stride(from: bitCount - 1, through: 0, by: -1) {
            bits.append((UInt32(value) >> shift) & 1 == 1)
        }
    }

    /// Octets bruts dans le tampon : le premier octet d'une paire est le
    /// poids faible du mot. Un octet isolé traîne un octet de bourrage —
    /// c'est précisément le cas que le décodeur compense (« taille impaire »).
    mutating func writeRaw(_ bytes: [UInt8]) {
        var i = 0
        while i + 1 < bytes.count {
            write(Int(bytes[i]) | Int(bytes[i + 1]) << 8, bitCount: 16)
            i += 2
        }
        if i < bytes.count {
            // L'octet isolé va en poids faible du mot (premier octet du
            // tampon) ; le bourrage en poids fort n'est jamais lu.
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

/// Morceaux XMem/LZX valides, encodés à la main contre `block.rs` —
/// exactement ce que le décodeur lit, pré-arbres et deltas compris.
enum LzxdBlockFixture {
    /// Premier morceau : bit E8 = 0, bloc verbatim (type `0b001`) dont
    /// l'arbre principal donne aux 256 octets une longueur de 8 — chaque
    /// octet est son propre code, les tokens sont les octets eux-mêmes.
    static func firstVerbatimChunk(content: [UInt8]) -> [UInt8] {
        var w = LzxdBitWriter()
        w.write(0, bitCount: 1)                 // pas de traduction E8
        writeVerbatimBlock(&w, content: content, firstTime: true)
        return w.bytes()
    }

    /// Morceau suivant : pas de bit E8 (lu une seule fois par flux), deltas
    /// nuls — les longueurs de 8 du premier bloc persistent dans le décodeur.
    static func continuationVerbatimChunk(content: [UInt8]) -> [UInt8] {
        var w = LzxdBitWriter()
        writeVerbatimBlock(&w, content: content, firstTime: false)
        return w.bytes()
    }

    /// Flux entier en un seul morceau : les blocs s'enchaînent bit à bit
    /// (contigus, sans réalignement entre blocs verbatim).
    static func combinedVerbatimStream(_ chunks: [[UInt8]]) -> [UInt8] {
        var w = LzxdBitWriter()
        w.write(0, bitCount: 1)
        writeVerbatimBlock(&w, content: chunks[0], firstTime: true)
        for chunk in chunks.dropFirst() {
            writeVerbatimBlock(&w, content: chunk, firstTime: false)
        }
        return w.bytes()
    }

    /// Bloc non compressé (type `0b011`) : en-tête, alignement au mot,
    /// R0/R1/R2 en u32 LE, puis les octets bruts.
    static func uncompressedChunk(content: [UInt8]) -> [UInt8] {
        var w = LzxdBitWriter()
        w.write(0, bitCount: 1)                 // pas de E8
        w.write(0b011, bitCount: 3)
        w.write(content.count, bitCount: 24)
        let used = 1 + 3 + 24
        w.write(0, bitCount: 16 - used % 16)    // align() saute la fin du mot
        for _ in 0..<3 {                        // R0 = R1 = R2 = 1
            w.write(1, bitCount: 16)
            w.write(0, bitCount: 16)
        }
        w.writeRaw(content)
        return w.bytes()
    }

    private static func writeVerbatimBlock(
        _ w: inout LzxdBitWriter, content: [UInt8], firstTime: Bool
    ) {
        w.write(0b001, bitCount: 3)             // type verbatim
        w.write(content.count, bitCount: 24)    // taille u24 BE (en éléments)

        // Arbre principal, 256 premiers éléments. Pré-arbre {0:1, 9:1} :
        // delta 0 = « 0 », delta 9 = « 1 ». Premier passage : 0 → 8 (c = 9)
        // sur chaque slot ; passages suivants : 8 → 8 (c = 0).
        for symbol in 0..<20 { w.write(symbol == 0 || symbol == 9 ? 1 : 0, bitCount: 4) }
        let deltaOne = firstTime ? 1 : 0
        for _ in 0..<256 { w.write(deltaOne, bitCount: 1) }

        // Arbre principal, éléments 256..512 (fenêtre kb64) : tous absents.
        for symbol in 0..<20 { w.write(symbol == 0 || symbol == 1 ? 1 : 0, bitCount: 4) }
        for _ in 0..<256 { w.write(0, bitCount: 1) }

        // Arbre des longueurs, 249 éléments : tous absents (aucun match).
        for symbol in 0..<20 { w.write(symbol == 0 || symbol == 1 ? 1 : 0, bitCount: 4) }
        for _ in 0..<249 { w.write(0, bitCount: 1) }

        // Tokens : chaque octet est son propre code canonique de 8 bits.
        for byte in content { w.write(Int(byte), bitCount: 8) }
    }
}

struct LzxdDecoderTests {
    @Test func emptyInputWithOutputIsCorrupt() {
        var d = LzxdDecoder(window: .kb64)
        #expect(throws: LzxdError.self) {
            _ = try d.decompressNext([UInt8]()[...], outputLength: 100)
        }
    }

    @Test func outputLengthMustBePositive() {
        var d = LzxdDecoder(window: .kb64)
        #expect(throws: LzxdError.self) {
            _ = try d.decompressNext([0x00, 0x01][...], outputLength: 0)
        }
    }

    @Test func verbatimChunkDecodesItsLiterals() throws {
        let content: [UInt8] = Array("Stardew".utf8)
        var d = LzxdDecoder(window: .kb64)
        let out = try d.decompressNext(
            LzxdBlockFixture.firstVerbatimChunk(content: content)[...],
            outputLength: content.count)
        #expect(Array(out) == content)
    }

    @Test func uncompressedBlockReadsRawBytes() throws {
        let content: [UInt8] = [UInt8(ascii: "x"), 0xFF, 0x42]
        var d = LzxdDecoder(window: .kb64)
        let out = try d.decompressNext(
            LzxdBlockFixture.uncompressedChunk(content: content)[...],
            outputLength: content.count)
        #expect(Array(out) == content)
    }

    @Test func decoderStateSurvivesAcrossChunks() throws {
        let first: [UInt8] = Array("Stardew ".utf8)
        let second: [UInt8] = Array("Valley".utf8)
        let combined = LzxdBlockFixture.combinedVerbatimStream([first, second])

        var whole = LzxdDecoder(window: .kb64)
        let full = try whole.decompressNext(
            combined[...], outputLength: first.count + second.count)

        // Deux morceaux séparés, même décodeur : la fenêtre, les arbres
        // canoniques (les deltas du 2e bloc se calculent sur les longueurs
        // du 1er) et le bit E8 lu une seule fois appartiennent au décodeur.
        var split = LzxdDecoder(window: .kb64)
        let a = Array(try split.decompressNext(
            LzxdBlockFixture.firstVerbatimChunk(content: first)[...],
            outputLength: first.count))
        let b = Array(try split.decompressNext(
            LzxdBlockFixture.continuationVerbatimChunk(content: second)[...],
            outputLength: second.count))
        #expect(a + b == Array(full))
        #expect(a + b == Array("Stardew Valley".utf8))
    }
}
