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
/// Encodage du contenu : compteurs de readers, ressources partagées,
/// index de reader et **longueurs de chaînes** en 7-bit little-endian
/// (`Read7BitEncodedInt`) ; seuls le compteur d'entrées du dictionnaire et
/// la version de chaque reader sont des `u32` LE.
///
/// Framing LZX : blocs de `0x8000` octets décompressés. Un bloc standard
/// commence par sa taille compressée `u16` BE ; le bloc **non standard**
/// — celui dont la sortie ne remplit pas un cadre entier — commence par le
/// marqueur d'un octet `0xff`, suivi de `frame_size u16` BE et
/// `block_size u16` BE. Les deux restent compressés : seule la taille de
/// sortie passée à `LzxdDecoder.decompressNext` change.
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

    private static let stringReaderName =
        "Microsoft.Xna.Framework.Content.StringReader"

    /// Plafonds hérités de la référence (spec §4).
    private static let maxEntries: UInt32 = 250_000

    public static func read(_ data: Data) throws -> [String: String] {
        let (names, opened) = try XnbContainer.open(data)
        var cursor = opened
        return try parseDictionary(names: names, cursor: &cursor)
    }

    // MARK: - Contenu typé

    private static func parseDictionary(
        names: [String], cursor: inout XnbCursor
    ) throws -> [String: String] {
        let readerCount = names.count
        let rootIndex = try cursor.vint()
        guard rootIndex >= 1, rootIndex <= readerCount else { throw ReadError.entryOverflow }
        guard isStringDictionaryReader(names[rootIndex - 1]) else {
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

    /// Le nom du reader racine, comparé **argument par argument** : le jeu
    /// qualifie chaque type générique par son assembly (`System.String,
    /// mscorlib, Version=…, PublicKeyToken=…`), la forme courte n'apparaît
    /// que dans nos fixtures. On exige le `DictionaryReader\`2` et deux
    /// `System.String` — un dictionnaire à valeurs entières reste refusé.
    private static func isStringDictionaryReader(_ name: String) -> Bool {
        let prefix = "Microsoft.Xna.Framework.Content.DictionaryReader`2[["
        guard name.hasPrefix(prefix), name.hasSuffix("]]") else { return false }
        let arguments = name.dropFirst(prefix.count).dropLast(2)
            .components(separatedBy: "],[")
        guard arguments.count == 2 else { return false }
        return arguments.allSatisfy { argument in
            argument.split(separator: ",", maxSplits: 1)[0]
                .trimmingCharacters(in: .whitespaces) == "System.String"
        }
    }

    /// Une chaîne de paire : index de reader 7-bit (0 = null → vide, sinon
    /// forcément le StringReader), puis la chaîne.
    private static func entryString(
        _ cursor: inout XnbCursor, stringReaderIndex: Int
    ) throws -> String {
        let index = try cursor.vint()
        guard index == 0 || index == stringReaderIndex else { throw ReadError.entryOverflow }
        return index == 0 ? "" : try cursor.string()
    }
}
