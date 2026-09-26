import Foundation

extension PerformanceOverlap {
    /// Le catalogue effectif (A5-T7, marche 2) : pour chaque paire des mods du
    /// catalogue, le résultat **mesuré en jeu** quand les deux figurent dans la
    /// carte de la sonde (chargés lors de sa dernière session), l'entrée
    /// **décompilée** sinon — mod en pause, non chargé, ou pas de sonde.
    ///
    /// Une paire mesurée existe si les deux mods partagent au moins 2 méthodes
    /// (seuil de la marche 1) ou si l'un patche le code de l'autre (dès 1).
    /// Rien d'autre que ces 5 mods : sur le parc réel, 219 paires de mods
    /// partagent ≥ 2 méthodes, surtout des frameworks qui ne « font pas le
    /// même travail ».
    public static func effectiveCatalog(base: [PerformanceOverlap] = PerformanceOverlap.catalog,
                                        map: ProbeHarmonyMap?) -> [PerformanceOverlap] {
        // Une carte écrite au lancement ne voit pas les patches posés au
        // chargement de la sauvegarde (1 214 méthodes contre 1 278 sur le
        // parc) ; la sonde l'écrit pourtant par-dessus la carte complète quand
        // on quitte à l'écran titre.
        guard let map, map.stage != "GameLaunched" else { return base }
        var members: [Member] = []
        for overlap in base {
            for member in [overlap.first, overlap.second]
            where !members.contains(where: { $0.uniqueId.caseInsensitiveCompare(member.uniqueId) == .orderedSame }) {
                members.append(member)
            }
        }
        var result: [PerformanceOverlap] = []
        for i in members.indices {
            for j in members.indices where j > i {
                let a = members[i], b = members[j]
                let catalogued = base.first { $0.member(a.uniqueId) != nil && $0.member(b.uniqueId) != nil }
                guard map.isLoaded(a.uniqueId), map.isLoaded(b.uniqueId) else {
                    if let catalogued { result.append(catalogued) }
                    continue
                }
                // L'ordre de la paire suit le catalogue quand il la connaît.
                let first = catalogued?.first ?? a
                let second = catalogued?.second ?? b
                if let measured = measure(first, second, in: map) { result.append(measured) }
            }
        }
        return result
    }

    private static func measure(_ a: Member, _ b: Member, in map: ProbeHarmonyMap) -> PerformanceOverlap? {
        let shared = map.sharedMethods(a.uniqueId, b.uniqueId)
        var codePatches: [CodePatch] = []
        for (patcher, patched) in [(a, b), (b, a)] {
            guard let assembly = patched.assemblyName else { continue }
            let methods = map.methods(patchedBy: patcher.uniqueId, inAssembly: assembly)
            if !methods.isEmpty {
                codePatches.append(CodePatch(patcher: patcher.uniqueId, patched: patched.uniqueId, methods: methods))
            }
        }
        let kept = shared.count >= 2 ? shared : []
        guard !kept.isEmpty || !codePatches.isEmpty else { return nil }
        func measured(_ member: Member) -> Member {
            Member(uniqueId: member.uniqueId,
                   measuredVersion: map.version(of: member.uniqueId) ?? member.measuredVersion,
                   assemblyName: member.assemblyName)
        }
        return PerformanceOverlap(first: measured(a), second: measured(b),
                                  sharedMethods: kept, conditionalMethods: [], conditionalOption: nil,
                                  measuredAt: map.capturedAt, codePatches: codePatches)
    }
}
