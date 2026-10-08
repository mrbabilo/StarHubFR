import SwiftUI

struct PerformanceSummarySection: View {
    @ObservedObject var localization: LocalizationStore
    var report: ProbePerformanceReport?
    var single: ProbePerformanceSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(localization.L(L10n.PerformanceEvidence.summary)).font(AppDesign.Font.headline(.semibold))
            if let report {
                source(report.before, key: L10n.Performance.before)
                source(report.after, key: L10n.Performance.after)
                WrapHStack(spacing: AppDesign.Spacing.sm) {
                    ForEach([ProbeMetric.frameP50, .frameP99, .workingSet], id: \.self) { metric in
                        if let result = report.metrics[metric] { tile(result, quality: report.quality[metric]) }
                    }
                }
                if report.metrics[.frameP50]?.locations.contains(where: \.admissible) == true {
                    Text(localization.L(L10n.PerformanceEvidence.balanced)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                }
                DisclosureGroup(localization.L(L10n.PerformanceEvidence.memoryTrend)) {
                    Text(localization.L(L10n.Performance.before)).font(AppDesign.Font.body(.semibold))
                    memory(report.memoryBefore)
                    Text(localization.L(L10n.Performance.after)).font(AppDesign.Font.body(.semibold))
                    memory(report.memoryAfter)
                }
                if let quality = report.quality[.frameP50] {
                    ForEach(Array(quality.reasons.enumerated()), id: \.offset) { _, reason in
                        Label(PerformanceMetricText.reason(reason, localization), systemImage: AppDesign.Status.info.symbol)
                            .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                    }
                }
            } else if let single {
                source(single.side, key: L10n.PerformanceEvidence.lastSession)
                ForEach([ProbeMetric.frameP50, .frameP99, .workingSet], id: \.self) { metric in
                    singleMetric(metric, summary: single)
                }
                DisclosureGroup(localization.L(L10n.PerformanceEvidence.details)) {
                    ForEach([ProbeMetric.fps, .work, .committed, .heap], id: \.self) { singleMetric($0, summary: single) }
                    memory(single.memory)
                }
                Text(localization.L(L10n.PerformanceEvidence.repeatAdvice))
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            } else {
                Text(localization.L(L10n.PerformanceEvidence.noSingle)).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ result: ProbeMetricResult, quality: ProbeComparisonQuality?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PerformanceMetricText.name(result.metric, localization)).font(AppDesign.Font.footnote)
            Text("\(number(result.before)) → \(number(result.after)) \(PerformanceMetricText.unit(result.metric, localization))")
                .font(AppDesign.Font.body(.semibold)).monospacedDigit()
            Label(PerformanceMetricText.outcome(result.outcome, localization), systemImage: PerformanceMetricText.symbol(result.outcome))
                .font(AppDesign.Font.footnote).foregroundStyle(PerformanceMetricText.tint(result.outcome))
            if let delta = result.delta, result.outcome != .incomparable && result.outcome != .unavailable {
                Text("Δ \(number(delta)) \(PerformanceMetricText.unit(result.metric, localization))"
                     + (result.percent.map { " (\(number($0)) %)" } ?? ""))
                    .font(AppDesign.Font.footnote).monospacedDigit()
            }
            if let quality { Text(PerformanceMetricText.quality(quality.level, localization)).font(AppDesign.Font.caption).foregroundStyle(.secondary) }
            if result.metric.isMemory { Text(localization.L(L10n.PerformanceEvidence.memoryNote)).font(AppDesign.Font.caption).foregroundStyle(.secondary) }
        }
        .frame(width: 225, alignment: .leading)
        .padding(AppDesign.Spacing.sm)
        .background(AppDesign.Color.controlBg, in: RoundedRectangle(cornerRadius: AppDesign.Radius.md))
    }

    private func singleMetric(_ metric: ProbeMetric, summary: ProbePerformanceSummary) -> some View {
        SplitRow {
            Text(PerformanceMetricText.name(metric, localization))
        } trailing: {
            Text("\(number(summary.metrics[metric]?.median)) \(PerformanceMetricText.unit(metric, localization))").monospacedDigit()
        }
        .font(AppDesign.Font.body)
    }

    private func source(_ side: ProbeSide, key: String) -> some View {
        Text("\(localization.L(key)) · \(PerformanceMetricText.source(side))")
            .font(AppDesign.Font.footnote).foregroundStyle(.secondary).textSelection(.enabled)
    }

    @ViewBuilder private func memory(_ segments: [ProbeMemoryTrend.Segment]) -> some View {
        Text(localization.L(L10n.PerformanceEvidence.memoryTrend)).font(AppDesign.Font.body(.semibold))
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            VStack(alignment: .leading, spacing: 2) {
                Text("\(segment.location) · \(segment.start.formatted(date: .omitted, time: .shortened)) → \(segment.end.formatted(date: .omitted, time: .shortened))")
                Text(String(format: localization.L(L10n.PerformanceEvidence.trendDetail), number(segment.slopeMBPerMinute), number(segment.deltaMB), segment.count))
                if segment.sampled { Text(localization.L(L10n.PerformanceEvidence.sampled)) }
            }.font(AppDesign.Font.footnote)
        }
        Text(localization.L(L10n.PerformanceEvidence.trendNote)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
    }

    private func number(_ value: Double?) -> String { PerformanceFormatting.number(value) }
}
