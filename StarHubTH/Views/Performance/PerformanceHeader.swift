import SwiftUI

struct PerformanceHeader: View {
    @ObservedObject var localization: LocalizationStore
    var store: ProbePerformanceStore
    var body: some View {
        PerformanceSummarySection(localization: localization, report: store.report, single: store.singleSummary)
    }
}
