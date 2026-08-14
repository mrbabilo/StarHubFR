import Testing
import Foundation
@testable import StarHubTHCore

/// Le champ `Version` d'un manifest existe sous deux formes, et l'app en
/// avait deux lectures divergentes : le scan les gérait toutes les deux, la
/// pose d'ancre à l'installation abandonnait en silence sur la forme objet.
/// Ces tests verrouillent la lecture unique.
struct ManifestVersionReaderTests {

    @Test func aStringVersionIsReadAsIs() {
        #expect(ManifestVersionReader.version(from: ["Version": "1.2.3"]) == "1.2.3")
    }

    @Test func theKeyIsMatchedRegardlessOfCase() {
        // Les manifests réels écrivent `Version`, `version`, parfois `VERSION`.
        #expect(ManifestVersionReader.version(from: ["version": "2.0"]) == "2.0")
    }

    @Test func anObjectVersionIsAssembled() {
        let manifest: [String: Any] = ["Version": ["MajorVersion": 1,
                                                   "MinorVersion": 2,
                                                   "PatchVersion": 3]]
        #expect(ManifestVersionReader.version(from: manifest) == "1.2.3")
    }

    @Test func missingObjectPartsFallBackLikeTheLibraryScanDoes() {
        // Mêmes défauts que le scan (majeure 1, le reste 0) : deux lectures qui
        // divergeraient sur ce point rendraient des chaînes différentes pour un
        // même manifest, ce que ce module existe pour empêcher.
        #expect(ManifestVersionReader.version(from: ["Version": [String: Any]()]) == "1.0.0")
        #expect(ManifestVersionReader.version(from: ["Version": ["MinorVersion": 5]]) == "1.5.0")
    }

    @Test func numericPartsWrittenAsStringsAreAccepted() {
        // Un manifest écrit à la main peut porter "1" plutôt que 1.
        let manifest: [String: Any] = ["Version": ["MajorVersion": "2",
                                                   "MinorVersion": "1",
                                                   "PatchVersion": "0"]]
        #expect(ManifestVersionReader.version(from: manifest) == "2.1.0")
    }

    @Test func anAbsentFieldYieldsNil() {
        #expect(ManifestVersionReader.version(from: ["Name": "X"]) == nil)
    }

    @Test func aBlankStringYieldsNilRatherThanAnEmptyVersion() {
        // Une version vide affirmerait « j'ai installé la version "" », ce qui
        // se comparerait ensuite à n'importe quoi.
        #expect(ManifestVersionReader.version(from: ["Version": "   "]) == nil)
        #expect(ManifestVersionReader.version(from: ["Version": ""]) == nil)
    }

    @Test func anUnreadableTypeYieldsNil() {
        #expect(ManifestVersionReader.version(from: ["Version": 42]) == nil)
        #expect(ManifestVersionReader.version(from: ["Version": [1, 2, 3]]) == nil)
    }
}
