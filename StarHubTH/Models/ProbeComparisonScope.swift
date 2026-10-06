import Foundation

/// Contexte partagé par l'analyse et les graphiques. Une absence reste explicite.
public struct ProbeComparisonScope: Equatable, Sendable {
    public enum Issue: String, Equatable, Sendable {
        case sameSelection, overlappingWindows, inventoryMissing, noSharedLocation
        case patchesUnknown, patchesDiffer, patchesMixed, probeVersionChanged
    }
    public let before: ProbeSide
    public let after: ProbeSide
    public let diff: ProbeInventoryDiff?
    public let locations: [String]
    public let issues: [Issue]

    public var incompatible: Bool {
        issues.contains { [.sameSelection, .overlappingWindows, .noSharedLocation,
                            .patchesDiffer, .patchesMixed].contains($0) }
    }

    public static func overlaps(_ a: ProbeSide, _ b: ProbeSide) -> Bool {
        if a.id == b.id { return true }
        guard a.session == b.session else { return false }
        let datesA = Set(a.minutes.compactMap { ProbeDate.parse($0.at) })
        if !datesA.isDisjoint(with: b.minutes.compactMap { ProbeDate.parse($0.at) }) { return true }
        guard let startA = a.start, let endA = a.end, let startB = b.start, let endB = b.end else { return false }
        return startA < endB && startB < endA
    }

    public static func make(before: ProbeSide, after: ProbeSide) -> Self {
        var issues: [Issue] = []
        if before.id == after.id { issues.append(.sameSelection) }
        if overlaps(before, after) { issues.append(.overlappingWindows) }
        let diff: ProbeInventoryDiff?
        if let a = before.inventory, let b = after.inventory {
            diff = ProbeInventoryDiffRule.between(
                ProbeInventoryLaunch(session: before.session, at: before.start, probe: nil, mods: Array(a.values)),
                ProbeInventoryLaunch(session: after.session, at: after.start, probe: nil, mods: Array(b.values)))
        } else { diff = nil; issues.append(.inventoryMissing) }
        if diff?.probeChanged == true { issues.append(.probeVersionChanged) }
        func locations(_ side: ProbeSide) -> Set<String> {
            Set(side.comparable.kept.compactMap(\.minute.location).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
        let common = locations(before).intersection(locations(after)).sorted()
        if common.isEmpty { issues.append(.noSharedLocation) }
        let a = Set(before.comparable.kept.map(\.patchesMeasured))
        let b = Set(after.comparable.kept.map(\.patchesMeasured))
        if a.isEmpty || b.isEmpty || a.contains(nil) || b.contains(nil) { issues.append(.patchesUnknown) }
        if Set(a.compactMap { $0 }).count > 1 || Set(b.compactMap { $0 }).count > 1 { issues.append(.patchesMixed) }
        if a != b { issues.append(.patchesDiffer) }
        return Self(before: before, after: after, diff: diff, locations: common, issues: issues)
    }
}
