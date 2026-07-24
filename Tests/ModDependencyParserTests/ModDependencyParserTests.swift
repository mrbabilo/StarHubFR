import Testing
import Foundation
@testable import StarHubTHCore

struct ModDependencyParserTests {
    @Test func parsesDependenciesArray() {
        let json: [String: Any] = ["Dependencies": [
            ["UniqueID": "Foo.Bar", "IsRequired": true],
            ["UniqueID": "Baz.Qux", "IsRequired": false],
        ]]
        #expect(ModDependencyParser.parse(manifest: json) == [
            ModDependency(uniqueId: "Foo.Bar", isRequired: true),
            ModDependency(uniqueId: "Baz.Qux", isRequired: false),
        ])
    }
    @Test func missingIsRequiredDefaultsToTrue() {
        let json: [String: Any] = ["Dependencies": [["UniqueID": "Foo.Bar"]]]
        #expect(ModDependencyParser.parse(manifest: json) == [ModDependency(uniqueId: "Foo.Bar", isRequired: true)])
    }
    @Test func contentPackForBecomesRequiredDependency() {
        let json: [String: Any] = ["ContentPackFor": ["UniqueID": "Pathoschild.ContentPatcher"]]
        #expect(ModDependencyParser.parse(manifest: json)
            == [ModDependency(uniqueId: "Pathoschild.ContentPatcher", isRequired: true)])
    }
    @Test func mergesBothSourcesDeduped() {
        // Same id appears as an OPTIONAL Dependencies entry AND as ContentPackFor
        // (always required) → requiredness is OR-ed to true, listed once.
        let json: [String: Any] = [
            "Dependencies": [["UniqueID": "Pathoschild.ContentPatcher", "IsRequired": false]],
            "ContentPackFor": ["UniqueID": "Pathoschild.ContentPatcher"],
        ]
        #expect(ModDependencyParser.parse(manifest: json)
            == [ModDependency(uniqueId: "Pathoschild.ContentPatcher", isRequired: true)])
    }
    @Test func emptyManifestYieldsNoDependencies() {
        #expect(ModDependencyParser.parse(manifest: [:]) == [])
    }
}
