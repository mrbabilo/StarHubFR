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
}
