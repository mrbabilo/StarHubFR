import Testing
import Foundation
@testable import StarHubTHCore

struct NexusModFileVersionTests {
    @Test func decodesVersionAndUploadedTimestamp() throws {
        let json = #"{"files":[{"file_id":174232,"category_id":1,"version":"1.2.0","uploaded_timestamp":1690096260}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        let file = NexusDownloadAPI.file(withId: 174232, in: list)
        #expect(file?.version == "1.2.0")
        #expect(file?.uploadedTimestamp == 1690096260)
    }

    @Test func toleratesMissingVersionAndTimestamp() throws {
        let json = #"{"files":[{"file_id":5,"category_id":4}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        let file = NexusDownloadAPI.file(withId: 5, in: list)
        #expect(file?.version == nil)
        #expect(file?.uploadedTimestamp == nil)
    }

    @Test func fileLookupReturnsNilWhenAbsent() throws {
        let json = #"{"files":[{"file_id":1,"category_id":1}]}"#.data(using: .utf8)!
        let list = try NexusDownloadAPI.decodeFileList(json)
        #expect(NexusDownloadAPI.file(withId: 999, in: list) == nil)
    }
}
