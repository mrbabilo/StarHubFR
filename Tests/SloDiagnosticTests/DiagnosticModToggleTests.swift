import Foundation
import Testing
@testable import StarHubTHCore

struct DiagnosticModToggleTests {
    @Test func togglesExactlyOneRootAndNeverTouchesDependencies() throws {
        let mods = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: mods) }
        for root in [".Pack", ".ExternalDependency", "EnabledDependent"] {
            try FileManager.default.createDirectory(at: mods.appendingPathComponent(root), withIntermediateDirectories: true)
        }
        #expect(DiagnosticModToggle.setEnabled(true, root: "Pack", modsRoot: mods))
        #expect(DiagnosticModToggle.enabled(root: "Pack", modsRoot: mods) == true)
        #expect(DiagnosticModToggle.enabled(root: "ExternalDependency", modsRoot: mods) == false)
        #expect(DiagnosticModToggle.setEnabled(false, root: "Pack", modsRoot: mods))
        #expect(DiagnosticModToggle.enabled(root: "EnabledDependent", modsRoot: mods) == true)
        #expect(!DiagnosticModToggle.setEnabled(true, root: "../Elsewhere", modsRoot: mods))
        try FileManager.default.createDirectory(at: mods.appendingPathComponent("Pack"), withIntermediateDirectories: true)
        #expect(DiagnosticModToggle.enabled(root: "Pack", modsRoot: mods) == nil)
        #expect(!DiagnosticModToggle.setEnabled(false, root: "Pack", modsRoot: mods))
    }
}
