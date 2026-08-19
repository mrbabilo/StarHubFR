import Testing
@testable import StarHubTHCore

/// Les fixtures de ce fichier suivent la sémantique **réelle** du flux XMem/LZX
/// (mots de 16 bits little-endian lus MSB-first), vérifiée contre les tests de
/// `bitstream.rs` — pas un modèle « octets MSB » intuitif qui décoderait du bruit.
struct LzxdBitstreamTests {
    @Test func readsMostSignificantBitFirst() throws {
        var s = LzxdBitstream([0b1011_0000])
        #expect(try s.readBit() == 1)
        #expect(try s.readBit() == 0)
        #expect(try s.readBit() == 1)
        #expect(try s.readBit() == 1)
    }

    @Test func readsWordsByteSwapped() throws {
        // Mot 0 = 0x8040 : les premiers bits viennent du SECOND octet.
        var s = LzxdBitstream([0b0100_0000, 0b1000_0000])
        #expect(try s.readBits(2) == 0b10)
        #expect(try s.readBits(14) == 0b00_0000_0100_0000)
    }

    @Test func peekDoesNotConsume() throws {
        var s = LzxdBitstream([0b1100_0000])
        #expect(try s.peekBits(2) == 0b11)
        #expect(try s.readBits(2) == 0b11)   // re-lisible après le peek
    }

    @Test func alignSkipsToNext16BitWordBoundary() throws {
        // Mots 0xA0F0 puis 0x0306 : align jette la fin du mot courant, pas de l'octet.
        var s = LzxdBitstream([0b1111_0000, 0b1010_0000, 0b0000_0110, 0b0000_0011])
        #expect(try s.readBits(5) == 0b10100)
        try s.align()                  // jette les 11 bits restants du mot 0
        #expect(try s.readBits(4) == 0b0000)   // début du mot 1
        #expect(try s.readBits(4) == 0b0011)
    }

    @Test func alignAtWordBoundaryConsumesAFullWord() throws {
        // Branche `remaining == 0` du Rust : align avale le mot suivant entier.
        var s = LzxdBitstream([0xFF, 0x00, 0x00, 0x00, 0b0110_0000, 0b1000_0000])
        #expect(try s.readBits(16) == 0x00FF)  // mot 0 consommé entier
        try s.align()                           // le mot 1 est avalé
        #expect(try s.readBits(4) == 0b1000)    // mot 2 = 0x8060
    }

    @Test func readU24BigEndianAcrossWords() throws {
        // Mots 0x162C puis 0x2468 : 4 bits, un u24 à cheval sur les deux mots, 4 bits.
        var s = LzxdBitstream([0x2C, 0x16, 0x68, 0x24])
        #expect(try s.readBits(4) == 0b0001)
        #expect(try s.readU24BE() == 0b0110_0010_1100_0010_0100_0110)
        #expect(try s.readBits(4) == 0b1000)
    }

    @Test func readU32LittleEndian() throws {
        var s = LzxdBitstream([0xEF, 0xBE, 0xAD, 0xDE])
        #expect(try s.readU32LE() == 0xDEAD_BEEF)
    }

    @Test func readRawFillsTheWholeBuffer() throws {
        var s = LzxdBitstream([0xAB, 0xCD])
        var out = [UInt8](repeating: 0, count: 2)
        try s.readRaw(into: &out)
        #expect(out == [0xAB, 0xCD])
        #expect(s.remainingBytes == 0)
    }

    @Test func overreadThrows() {
        var s = LzxdBitstream([0x00])
        #expect(throws: LzxdBitstream.Error.outOfData) { try s.readBits(9) }
    }

    @Test func singleByteTailYieldsEightBitsThenThrows() throws {
        // Un octet isolé en fin de tampon livre ses 8 bits réels, pas un mot fantôme.
        var s = LzxdBitstream([0b1010_0100])
        #expect(try s.readBits(8) == 0b1010_0100)
        #expect(throws: LzxdBitstream.Error.outOfData) { try s.readBit() }
    }

    @Test func readEqualsPeek() throws {
        let bytes: [UInt8] = [0b1101_1101, 0b1011_1011, 0b0111_0111, 0b0011_1011]
        for offset in 0...12 {
            for size in 0...12 {
                var s = LzxdBitstream(bytes)
                _ = try s.readBits(offset)
                let peeked = s.peekBits(size)
                #expect(try s.readBits(size) == peeked)
            }
        }
    }
}
