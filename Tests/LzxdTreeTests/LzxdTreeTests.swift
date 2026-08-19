import Testing
@testable import StarHubTHCore

/// Assemble un flux de bits XMem/LZX : bits MSB-first dans des mots de
/// 16 bits little-endian, **mots complets seulement** — aucun bit fantôme
/// en fin de flux, toute surlecture lève `outOfData`.
private struct LzxdBitWriter {
    private var bits: [Bool] = []

    mutating func write(_ value: Int, bitCount: Int) {
        for shift in stride(from: bitCount - 1, through: 0, by: -1) {
            bits.append((UInt32(value) >> shift) & 1 == 1)
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

struct LzxdTreeTests {
    @Test func decodesFromPathLengths() throws {
        // Longueurs canoniques {0:2, 1:2, 2:1} → codes 10, 11, 0.
        let tree = try LzxdTree(pathLengths: [2, 2, 1])
        var bits = LzxdBitstream([0b0000_0000])       // premier bit = 0 → symbole 2
        #expect(try tree.decodeElement(with: &bits) == 2)
        var two = LzxdBitstream([0b1000_0000])        // « 10 » → symbole 0
        #expect(try tree.decodeElement(with: &two) == 0)
    }

    @Test func rejectsIncompleteAndOversubscribedLengths() {
        #expect(throws: LzxdTreeError.invalidPathLengths) {
            try LzxdTree(pathLengths: [1, 1, 1])   // sursouscrit : 3 codes de 1 bit
        }
        #expect(throws: LzxdTreeError.invalidPathLengths) {
            try LzxdTree(pathLengths: [2, 0])      // incomplet : la moitié de la table vide
        }
    }

    @Test func emptyTreeYieldsNilThenThrowsOnCreate() throws {
        let canonical = LzxdCanonicalTree(slotCount: 5)
        #expect(try canonical.createInstanceAllowEmpty() == nil)
        #expect(throws: LzxdTreeError.emptyTree) { try canonical.createInstance() }
    }

    /// Écrit les 20 longueurs de pré-arbre (4 bits chacune, ordre des symboles).
    private func writePretreeLengths(_ w: inout LzxdBitWriter, lengthOf: (Int) -> Int) {
        for symbol in 0..<20 { w.write(lengthOf(symbol), bitCount: 4) }
    }

    @Test func updateRangeReadsPretreeEncodedDeltas() throws {
        // Pré-arbre {15:1, 0:2, 16:2} — complet (Kraft = 1) :
        // codes 15 = « 0 », 0 = « 10 », 16 = « 11 ».
        var w = LzxdBitWriter()
        writePretreeLengths(&w) { symbol in
            symbol == 15 ? 1 : (symbol == 0 || symbol == 16 ? 2 : 0)
        }
        // Deltas sur un arbre vierge : (17 + 0 − code) % 17.
        // 15, 15, 16, 0 → nouvelles longueurs [2, 2, 1, 0].
        w.write(0b0, bitCount: 1)    // 15
        w.write(0b0, bitCount: 1)    // 15
        w.write(0b11, bitCount: 2)   // 16
        w.write(0b10, bitCount: 2)   // 0

        var canonical = LzxdCanonicalTree(slotCount: 4)
        var stream = LzxdBitstream(w.bytes())
        try canonical.updateRange(withPretree: &stream, range: 0..<4)
        #expect(canonical.pathLengths == [2, 2, 1, 0])

        // L'arbre instancié décode : « 0 »→2, « 10 »→0, « 11 »→1.
        let tree = try canonical.createInstance()
        var dw = LzxdBitWriter()
        dw.write(0, bitCount: 1)
        dw.write(0b10, bitCount: 2)
        dw.write(0b11, bitCount: 2)
        var ds = LzxdBitstream(dw.bytes())
        #expect(try tree.decodeElement(with: &ds) == 2)
        #expect(try tree.decodeElement(with: &ds) == 0)
        #expect(try tree.decodeElement(with: &ds) == 1)
    }

    @Test func updateRangeZeroRunsEmptyTheTree() throws {
        var canonical = LzxdCanonicalTree(slotCount: 4)

        // Premier passage : deltas 15, 15, 16, 0 → [2, 2, 1, 0].
        var first = LzxdBitWriter()
        writePretreeLengths(&first) { symbol in
            symbol == 15 ? 1 : (symbol == 0 || symbol == 16 ? 2 : 0)
        }
        first.write(0, bitCount: 1)
        first.write(0, bitCount: 1)
        first.write(0b11, bitCount: 2)
        first.write(0b10, bitCount: 2)
        var firstStream = LzxdBitstream(first.bytes())
        try canonical.updateRange(withPretree: &firstStream, range: 0..<4)
        #expect(canonical.pathLengths == [2, 2, 1, 0])

        // Second passage : code 17 (run de zéros) — pré-arbre {1:1, 17:1} :
        // 1 = « 0 », 17 = « 1 ». zeros = 0 → 4 slots remis à zéro d'un coup.
        var second = LzxdBitWriter()
        writePretreeLengths(&second) { symbol in symbol == 1 || symbol == 17 ? 1 : 0 }
        second.write(1, bitCount: 1)
        second.write(0, bitCount: 4)
        var secondStream = LzxdBitstream(second.bytes())
        try canonical.updateRange(withPretree: &secondStream, range: 0..<4)
        #expect(canonical.pathLengths == [0, 0, 0, 0])
        #expect(try canonical.createInstanceAllowEmpty() == nil)
    }

    @Test func updateRangeCode19RepeatsADelta() throws {
        // Pré-arbre {19:1, 1:2, 2:2} : 19 = « 0 », 1 = « 10 », 2 = « 11 ».
        var w = LzxdBitWriter()
        writePretreeLengths(&w) { symbol in
            symbol == 19 ? 1 : (symbol == 1 || symbol == 2 ? 2 : 0)
        }
        w.write(0, bitCount: 1)     // code 19
        w.write(1, bitCount: 1)     // same = 1 → 5 slots
        w.write(0b10, bitCount: 2)  // delta 1 → valeur (17 − 1) % 17 = 16
        w.write(0b11, bitCount: 2)  // delta 2 → 15 sur le 6e slot

        var canonical = LzxdCanonicalTree(slotCount: 6)
        var stream = LzxdBitstream(w.bytes())
        try canonical.updateRange(withPretree: &stream, range: 0..<6)
        #expect(canonical.pathLengths == [16, 16, 16, 16, 16, 15])
    }

    @Test func updateRangeRejectsRunsBeyondTheTree() {
        var w = LzxdBitWriter()
        writePretreeLengths(&w) { symbol in symbol == 1 || symbol == 17 ? 1 : 0 }
        w.write(1, bitCount: 1)   // code 17
        w.write(4, bitCount: 4)   // zeros = 4 → run de 8 slots > 4

        var canonical = LzxdCanonicalTree(slotCount: 4)
        var stream = LzxdBitstream(w.bytes())
        #expect(throws: LzxdTreeError.invalidPretreeRle) {
            try canonical.updateRange(withPretree: &stream, range: 0..<4)
        }
    }
}
