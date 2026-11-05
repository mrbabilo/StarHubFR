import Foundation
import Testing
@testable import StarHubTHCore

/// X156 — macOS ne déclare pas le type RAR : sans déclaration dans l'app, un
/// `.rar` reçoit un type dynamique sur un Mac sans app tierce qui le déclare,
/// et le Dock refuse de le déposer sur StarHubFR.
struct ArchiveDocumentTypesTests {
    private static func infoPlist() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theRarTypeOpenedByTheAppIsImported() throws {
        let plist = try Self.infoPlist()
        let documents = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let opened = documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        #expect(opened.contains("com.rarlab.rar-archive"))

        let imported = plist["UTImportedTypeDeclarations"] as? [[String: Any]] ?? []
        let rar = try #require(imported.first { $0["UTTypeIdentifier"] as? String == "com.rarlab.rar-archive" })
        let tags = try #require(rar["UTTypeTagSpecification"] as? [String: Any])
        #expect(tags["public.filename-extension"] as? [String] == ["rar"])
        let conforms = rar["UTTypeConformsTo"] as? [String] ?? []
        #expect(conforms.contains("public.data"))
        #expect(conforms.contains("public.archive"))
    }

    /// Un format que l'installeur lit doit rester ouvrable depuis le Dock.
    @Test func everyArchiveFormatTheInstallerReadsHasADocumentType() throws {
        let plist = try Self.infoPlist()
        let documents = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let opened = Set(documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        let byExtension = ["zip": "public.zip-archive", "7z": "org.7-zip.7-zip-archive", "rar": "com.rarlab.rar-archive"]
        for format in ModZipInstaller.supportedExtensions {
            let type = try #require(byExtension[format], "format sans type connu : \(format)")
            #expect(opened.contains(type))
        }
    }
}
