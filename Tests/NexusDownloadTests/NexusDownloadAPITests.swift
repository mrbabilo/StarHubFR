import Testing
import Foundation
@testable import StarHubTHCore

struct NexusDownloadAPITests {
    @Test func premiumEndpointHasNoQuery() {
        let e = NexusDownloadAPI.downloadLinkEndpoint(game: "stardewvalley", modId: 41318, fileId: 174232, key: nil, expires: nil)
        #expect(e == "/games/stardewvalley/mods/41318/files/174232/download_link.json")
    }

    @Test func freeEndpointCarriesKeyAndExpires() {
        let e = NexusDownloadAPI.downloadLinkEndpoint(game: "stardewvalley", modId: 41318, fileId: 174232, key: "abc123", expires: 1666593200)
        #expect(e == "/games/stardewvalley/mods/41318/files/174232/download_link.json?key=abc123&expires=1666593200")
    }

    @Test func decodesDownloadLinks() throws {
        let json = #"[{"name":"CDN","short_name":"Nexus CDN","URI":"https://cdn.example/file.zip"}]"#.data(using: .utf8)!
        let links = try NexusDownloadAPI.decodeLinks(json)
        #expect(links.first?.URI == "https://cdn.example/file.zip")
    }

    @Test func picksMainFileCategoryOne() throws {
        let json = #"{"files":[{"file_id":1,"category_id":4},{"file_id":2,"category_id":1}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.pickPrimaryFileId(list) == 2)
    }

    @Test func fallsBackToFirstFileWhenNoMain() throws {
        let json = #"{"files":[{"file_id":7,"category_id":4}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.pickPrimaryFileId(list) == 7)
    }

    @Test func pickPrimaryFileIdIsNilForEmptyList() throws {
        let json = #"{"files":[]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.pickPrimaryFileId(list) == nil)
    }

    @Test func freeEndpointPercentEncodesSpecialKeyChars() {
        let e = NexusDownloadAPI.downloadLinkEndpoint(game: "stardewvalley", modId: 41318, fileId: 174232, key: "a&b=c+d", expires: 1666593200)
        #expect(e == "/games/stardewvalley/mods/41318/files/174232/download_link.json?key=a%26b%3Dc%2Bd&expires=1666593200")
    }

    // X8 — le picker de fichier principal pour la comparaison de version doit
    // prendre le MAIN le plus récent, pas le premier renvoyé.

    @Test func pickLatestMainFilePrefersNewestMainByTimestamp() throws {
        let json = #"{"files":[{"file_id":1,"category_id":1,"uploaded_timestamp":100,"version":"1.0.0"},{"file_id":2,"category_id":1,"uploaded_timestamp":200,"version":"1.5.0"},{"file_id":3,"category_id":6,"uploaded_timestamp":300,"version":"2.0.0"}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        let latest = NexusDownloadAPI.pickLatestMainFile(list)
        #expect(latest?.fileId == 2)
        #expect(latest?.version == "1.5.0")
    }

    @Test func pickLatestMainFileFallsBackToNewestOfAllWhenNoMain() throws {
        let json = #"{"files":[{"file_id":4,"category_id":6,"uploaded_timestamp":100,"version":"1.0.0"},{"file_id":5,"category_id":3,"uploaded_timestamp":200,"version":"1.5.0"}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.pickLatestMainFile(list)?.fileId == 5)
    }

    @Test func pickLatestMainFileTreatsMissingTimestampAsOldest() throws {
        let json = #"{"files":[{"file_id":1,"category_id":1,"version":"1.0.0"},{"file_id":2,"category_id":1,"uploaded_timestamp":100,"version":"1.1.0"}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.pickLatestMainFile(list)?.fileId == 2)
    }

    @Test func pickLatestMainFileIsNilForEmptyList() throws {
        let json = #"{"files":[]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.pickLatestMainFile(list) == nil)
    }

    @Test func decodesUploadedTimestampAndCategoryName() throws {
        let json = #"{"files":[{"file_id":24001,"category_id":1,"category_name":"MAIN","version":"2.4.1","mod_version":"2.4","uploaded_timestamp":1725000000}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        let file = try #require(list.files.first)
        #expect(file.uploadedTimestamp == 1725000000)
        #expect(file.categoryName == "MAIN")
        #expect(file.version == "2.4.1")
    }

    // Le téléchargement à fileId nil (install direct, traductions) doit lui
    // aussi prendre le MAIN le plus récent — pas le premier renvoyé.

    @Test func pickLatestMainFileIdPrefersNewestMain() throws {
        let json = #"{"files":[{"file_id":11,"category_id":1,"uploaded_timestamp":100,"version":"1.0.0"},{"file_id":12,"category_id":1,"uploaded_timestamp":300,"version":"2.0.0"},{"file_id":13,"category_id":1,"uploaded_timestamp":200,"version":"1.5.0"}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.pickLatestMainFileId(list) == 12)
    }

    @Test func pickLatestMainFileIdIsNilForEmptyList() throws {
        let json = #"{"files":[]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.pickLatestMainFileId(list) == nil)
    }
}
