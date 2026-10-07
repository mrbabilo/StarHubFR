import Foundation
import Testing
@testable import StarHubTHCore

struct StardropiumMemoryTests {
    private let first = "[14:44:16 INFO  Stardropium] [Morning Memory Optimizer (Background)] RAM: 655 MB -> 660 MB (Managed Heap: 3445 MB -> 3444 MB, 0 cached textures purged/bounded)."
    private let second = "[14:54:12 INFO  Stardropium] [Morning Memory Optimizer (Background)] RAM: 1561 MB -> 1565 MB (Managed Heap: 3749 MB -> 3751 MB, 0 cached textures purged/bounded)."

    @Test func realSessionPreservesIncreasesAndDistinctMetrics() throws {
        let report = StardropiumMemoryReport.parse("""
        [14:36:40 TRACE SMAPI] Log started at 2026-10-07T12:36:40 UTC
        [14:37:06 INFO  SMAPI]    Stardropium 0.2.2-beta by Arshia1381 | Performance
        \(first)
        \(second)
        """)
        #expect(report.samples.count == 2)
        #expect(report.version == "0.2.2-beta")
        #expect(report.sessionStart != nil)
        let sample = try #require(report.samples.last)
        #expect(sample.time == "14:54:12")
        #expect(sample.residentBefore == 1561)
        #expect(sample.residentAfter == 1565)
        #expect(sample.residentDelta == 4)
        #expect(sample.managedDelta == 2)
        #expect(report.samples.first?.managedDelta == -1)
        #expect(sample.purgedTextures == 0)
        #expect(!report.lowMemoryProfileDetected)
        #expect(report.unreadableSamples == 0)
    }

    @Test func rejectsWrongSourceMalformedAndImpossibleValues() {
        let text = [first.replacingOccurrences(of: "INFO  Stardropium", with: "INFO  OtherMod"),
                    first.replacingOccurrences(of: "655 MB", with: "-655 MB"),
                    first.replacingOccurrences(of: "14:44:16", with: "25:44:16"),
                    first.replacingOccurrences(of: "660 MB", with: "NaN MB"),
                    first.replacingOccurrences(of: "INFO  Stardropium", with: "ERROR Stardropium")].joined(separator: "\n")
        let report = StardropiumMemoryReport.parse(text)
        #expect(report.samples.isEmpty)
        #expect(report.unreadableSamples == 3)
    }

    @Test func profileRequiresItsOwnSourceAndEvidence() {
        let message = "Detected low-memory / unified memory device (<= 8GB RAM). Activating Low Memory & Unified Memory Profile (256 MB texture cache limit, active SinZ LRU bounding)."
        #expect(!StardropiumMemoryReport.parse("[10:00:00 INFO Other] \(message)").lowMemoryProfileDetected)
        #expect(StardropiumMemoryReport.parse("[10:00:00 INFO Stardropium] \(message)").lowMemoryProfileDetected)
        #expect(StardropiumMemoryReport.parse("").samples.isEmpty)
    }

    @Test func preservesFileOrderAcrossMidnightAndSameSecond() {
        let report = StardropiumMemoryReport.parse([first.replacingOccurrences(of: "14:44:16", with: "23:59:59"),
            second.replacingOccurrences(of: "14:54:12", with: "00:00:01"), second.replacingOccurrences(of: "14:54:12", with: "00:00:01")].joined(separator: "\n"))
        #expect(report.samples.map(\.time) == ["23:59:59", "00:00:01", "00:00:01"])
        #expect(Set(report.samples.map(\.id)).count == 3)
    }
}
