import SwiftUI
import Charts

/// Last guided diagnostic, or latest SMAPI journal. Separate from probe comparisons.
struct PerformanceStardropiumMemorySection: View {
    var viewModel: StarHubTHViewModel
    @ObservedObject var localization: LocalizationStore
    var store: SessionEnvironmentStore
    var diagnostic: SloDiagnosticSessionStore
    let runtime: () -> SloDiagnosticRuntime
    private typealias Keys = L10n.StardropiumMemory

    var body: some View {
        PerformanceCard {
            Text(localization.L(Keys.title)).font(AppDesign.Font.headline(.semibold))
            PerformanceStardropiumDiagnosticControls(viewModel: viewModel, localization: localization,
                                                    store: diagnostic, runtime: runtime)
            Text(localization.L(diagnostic.memoryReceipt == nil ? Keys.source : L10n.StardropiumDiagnostic.savedSource)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            if let receipt = diagnostic.memoryReceipt {
                Text(String(format: localization.L(L10n.StardropiumDiagnostic.savedAt),
                            receipt.completedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                contents(receipt.report)
            } else if store.status != .ready {
                ProgressView().controlSize(.small)
            } else if let environment = store.report {
                contents(environment.stardropiumMemory)
            } else {
                Text(localization.L(Keys.missing)).foregroundStyle(.secondary)
            }
        }
    }

    private func contents(_ report: StardropiumMemoryReport) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
            Text(report.sessionStart.map {
                String(format: localization.L(Keys.session), $0.formatted(date: .abbreviated, time: .shortened))
            } ?? localization.L(Keys.unknownDate))
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            Text(String(format: localization.L(Keys.version),
                        report.version ?? localization.L(Keys.unknownVersion), report.samples.count))
                .font(AppDesign.Font.footnote)
            Text(localization.L(report.lowMemoryProfileDetected ? Keys.profileDetected : Keys.profileUnknown))
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            if let latest = report.samples.last {
                Text(localization.L(Keys.latest)).font(AppDesign.Font.body(.semibold))
                Text(localization.L(latest.residentDelta > 0 ? Keys.residentRise
                                    : latest.residentDelta < 0 ? Keys.residentFall : Keys.residentStable))
                    .font(AppDesign.Font.body)
                reading(latest)
                graph(report.samples, managed: false)
                graph(report.samples, managed: true)
                Text(localization.L(Keys.note)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                Text(localization.L(Keys.metricsHelp)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
                DisclosureGroup(localization.L(Keys.details)) {
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.md) {
                        ForEach(report.samples) { sample in reading(sample) }
                    }.padding(.top, AppDesign.Spacing.sm)
                }
            } else {
                Text(localization.L(diagnostic.memoryReceipt == nil ? Keys.empty : L10n.StardropiumDiagnostic.noReadings)).foregroundStyle(.secondary)
            }
            if report.unreadableSamples > 0 {
                Text(String(format: localization.L(Keys.unreadable), report.unreadableSamples))
                    .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func reading(_ sample: StardropiumMemorySample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: localization.L(Keys.sample), sample.id + 1, sample.time))
                .font(AppDesign.Font.footnote(.semibold))
            metric(Keys.resident, before: sample.residentBefore, after: sample.residentAfter)
            metric(Keys.managed, before: sample.managedBefore, after: sample.managedAfter)
            Text(String(format: localization.L(Keys.textures), sample.purgedTextures))
                .font(AppDesign.Font.footnote).foregroundStyle(.secondary)
        }.textSelection(.enabled)
    }

    private func metric(_ key: String, before: Double, after: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localization.L(key)).font(AppDesign.Font.footnote).foregroundStyle(.secondary)
            Text(String(format: localization.L(Keys.values), number(before), number(after), signed(after - before)))
                .font(AppDesign.Font.body).monospacedDigit()
        }
    }

    private func graph(_ samples: [StardropiumMemorySample], managed: Bool) -> some View {
        let name = localization.L(managed ? Keys.managed : Keys.resident)
        let before = localization.L(Keys.before), after = localization.L(Keys.after)
        return VStack(alignment: .leading, spacing: 4) {
            Text(name).font(AppDesign.Font.body(.semibold))
            Chart(samples) { sample in
                PointMark(x: .value(localization.L(Keys.reading), sample.id + 1),
                          y: .value(localization.L(Keys.units), managed ? sample.managedBefore : sample.residentBefore))
                    .foregroundStyle(by: .value(localization.L(Keys.reading), before))
                    .symbol(by: .value(localization.L(Keys.reading), before))
                PointMark(x: .value(localization.L(Keys.reading), sample.id + 1),
                          y: .value(localization.L(Keys.units), managed ? sample.managedAfter : sample.residentAfter))
                    .foregroundStyle(by: .value(localization.L(Keys.reading), after))
                    .symbol(by: .value(localization.L(Keys.reading), after))
            }
            .chartForegroundStyleScale([before: AppDesign.Chart.before, after: AppDesign.Chart.after])
            .chartXScale(domain: 0...(samples.count + 1))
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 1, through: samples.count,
                                               by: max(1, (samples.count + 5) / 6))))
            }
            .chartXAxisLabel(localization.L(Keys.reading))
            .chartYAxisLabel(localization.L(Keys.units))
            .chartLegend(position: .bottom)
            .frame(height: 170)
            .accessibilityLabel(name)
        }
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func signed(_ value: Double) -> String {
        value > 0 ? "+" + number(value) : number(value)
    }
}
