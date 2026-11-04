import Compression
import Foundation

/// X138 — ce que l'app lit dans les fichiers de PureBinarySave. Format relevé
/// sur la 1.0.10 : 28 octets d'en-tête (`PPBS`, version et options sur 2 octets
/// chacune, taille décodée, taille compressée, somme de contrôle, date), puis
/// le XML de la partie en Brotli.
extension PureBinarySave {
    private static let headerSize = 28
    /// La taille décodée vient du fichier : un `.bin` abîmé ne doit pas
    /// réclamer 4 Go. Les parties du parc font de 10 à 40 Mo.
    private static let maximumDecodedSize = 512 * 1024 * 1024

    /// Le XML d'un fichier `.bin`, ou `nil` s'il n'est pas lisible en entier.
    static func decoded(_ file: Data) -> Data? {
        let bytes = [UInt8](file)
        guard bytes.count > headerSize, bytes.starts(with: Array("PPBS".utf8)) else { return nil }
        func size(at offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        let decodedSize = size(at: 8), compressedSize = size(at: 12)
        guard decodedSize > 0, decodedSize <= maximumDecodedSize,
              compressedSize == bytes.count - headerSize else { return nil }
        // Un octet de marge : une taille déclarée trop petite remplirait le
        // tampon exactement et passerait pour un décodage complet.
        var output = [UInt8](repeating: 0, count: decodedSize + 1)
        let written = bytes.withUnsafeBufferPointer { source in
            compression_decode_buffer(&output, output.count, source.baseAddress! + headerSize,
                                      compressedSize, nil, COMPRESSION_BROTLI)
        }
        return written == decodedSize ? Data(output[0..<written]) : nil
    }

    /// Le texte de la partie : le XML, ou le `.bin` quand le XML n'est qu'un
    /// talon. Pendant cette fenêtre, la page Parties lisait un fermier
    /// « Unknown ».
    static func readableText(of mainSave: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: mainSave.path) else { return nil }
        if !isCompleteSave(data), let file = FileManager.default.contents(atPath: binaryFiles(of: mainSave)[0].path),
           let inner = decoded(file), isCompleteSave(inner) {
            return String(data: inner, encoding: .utf8)
        }
        return String(data: data, encoding: .utf8)
    }

    /// Le jour de jeu d'un `SaveGameInfo`, compté depuis le début de la partie.
    private static func gameDay(in text: String) -> Int? {
        func value(_ tag: String) -> Int? {
            guard let open = text.range(of: "<\(tag)>"),
                  let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex) else { return nil }
            return Int(text[open.upperBound..<close.lowerBound])
        }
        guard let year = value("yearForSaveGame"), let season = value("seasonForSaveGame"),
              let day = value("dayOfMonthForSaveGame") else { return nil }
        return (year - 1) * 112 + season * 28 + day
    }

    /// De combien de jours de jeu le `.bin` retarde sur la partie, ou `nil`
    /// s'il ne retarde pas. La date de jeu et non celle du fichier : le mod
    /// recopie le XML quelques secondes après le `.bin`, et son délai se règle.
    /// C'est le `SaveGameInfo` qu'on compare, 35 Ko contre 10 Mo.
    static func daysBehind(_ mainSave: URL) -> Int? {
        let folder = mainSave.deletingLastPathComponent()
        let manager = FileManager.default
        guard manager.fileExists(atPath: binaryFiles(of: mainSave)[0].path),
              let xml = manager.contents(atPath: folder.appendingPathComponent("SaveGameInfo").path),
              let file = manager.contents(atPath: folder.appendingPathComponent("SaveGameInfo.bin").path),
              let inner = decoded(file),
              let xmlDay = gameDay(in: String(decoding: xml, as: UTF8.self)),
              let binDay = gameDay(in: String(decoding: inner, as: UTF8.self)),
              xmlDay > binDay else { return nil }
        return xmlDay - binDay
    }

    /// Une partie jouée sans le mod : il la ramènerait au jour de son `.bin`.
    public struct StaleSave: Equatable, Sendable {
        public let name: String
        public let path: String
        public let daysBehind: Int
    }

    static func staleSaves(_ saves: [(name: String, url: URL)]) -> [StaleSave] {
        saves.compactMap { save in
            daysBehind(save.url).map { StaleSave(name: save.name, path: save.url.path, daysBehind: $0) }
        }
    }

    /// Écarte les `.bin` des parties qui retardent encore : le jeu a pu tourner
    /// depuis l'alerte, et un `.bin` à jour porte la partie.
    static func setAsideStale(_ paths: [String], setAside: (URL) throws -> Void = trash) {
        for url in paths.map({ URL(fileURLWithPath: $0) }) where daysBehind(url) != nil {
            setAsideBinaries(of: url, setAside: setAside)
        }
    }

    /// Dans une copie toute neuve : ses `.bin` et ses caches portent le nom de
    /// l'original, le mod ne les relirait pas, et `SaveGameInfo.bin` afficherait
    /// l'ancien nom. Rien de l'original n'est touché.
    static func dropBinaries(named baseName: String, in copy: URL) {
        let manager = FileManager.default
        let names: [String]
        do { names = try manager.contentsOfDirectory(atPath: copy.path) } catch { return }
        for name in names where name.hasPrefix(baseName + ".") || name.hasPrefix("SaveGameInfo.") {
            guard [".bin", ".bin.bak", ".bin.tmp"].contains(where: name.hasSuffix) else { continue }
            do { try manager.removeItem(at: copy.appendingPathComponent(name)) } catch { continue }
        }
    }
}
