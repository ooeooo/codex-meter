import Charts
import CodexMeterCore
import SwiftUI

struct AccountUsageAnalyticsView: View {
    @ObservedObject var store: UsageStore
    @State private var searchDate = ""
    @State private var onlyActive = false
    @State private var sort: AccountUsageSort = .newest
    @State private var selectedDay: String?
    @State private var accountTotalsExpanded = false

    var body: some View {
        ScrollView {
            analyticsContent
        }
        .frame(height: panelHeight)
        .onAppear { Task { await store.refreshAnalytics() } }
        .onChange(of: store.analyticsRange) { _ in selectedDay = nil }
    }

    private var panelHeight: CGFloat {
        guard let usage = store.analytics else { return 220 }
        if usage.days == nil { return accountTotalsExpanded ? 300 : 220 }
        return 520
    }

    private var analyticsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(MeterLocalization.text("Account usage"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker(MeterLocalization.text("Period"), selection: $store.analyticsRange) {
                    ForEach(AccountUsageRange.allCases) { range in Text(range.title).tag(range) }
                }
                .pickerStyle(.segmented)
                .frame(width: 145)
            }
            if let usage = store.analytics {
                report(usage)
            } else if store.isLoadingAnalytics {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(MeterLocalization.text("Loading account history…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            } else if store.analyticsError == nil {
                Text(MeterLocalization.text("Read daily usage from your Codex account."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let error = store.analyticsError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(MeterLocalization.text("Account analytics unavailable"), systemImage: "exclamationmark.circle")
                        .font(.system(size: 11, weight: .medium))
                    Text(error).font(.system(size: 10))
                    HStack {
                        Button(MeterLocalization.text("Retry")) { Task { await store.refreshAnalytics(force: true) } }
                            .disabled(store.isLoadingAnalytics)
                        Spacer()
                        Button(MeterLocalization.text("Open Codex settings"), action: store.openCodex)
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(MeterLocalization.text("Account token history from Codex · dates follow Codex's daily buckets · refreshes every ten minutes"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    @ViewBuilder
    private func report(_ usage: AccountUsagePayload) -> some View {
        let report = usage.report(range: store.analyticsRange)
        if report.hasDailyDetail {
            HStack(spacing: 16) {
                metric(title: MeterLocalization.text(report.reportedDays == report.days.count ? "Period total" : "Reported total"), value: report.totalTokens)
                Spacer(minLength: 0)
                metric(title: MeterLocalization.text("Daily peak"), value: report.peakTokens)
            }
            if report.reportedDays > 0 {
                dailyChart(report)
            }
            Text(MeterLocalization.format("%d of %d days reported · %d active days", report.reportedDays, report.days.count, report.activeDays))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if report.reportedDays < report.days.count {
                Text(MeterLocalization.text("Missing days are not counted as zero. Totals include reported days only."))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            details(report)
        } else {
            Text(MeterLocalization.text("Codex did not provide daily detail for this account. Account totals are shown below."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        DisclosureGroup(isExpanded: $accountTotalsExpanded) {
            VStack(spacing: 6) {
                totalRow("Lifetime tokens", value: usage.summary.lifetimeTokens)
                totalRow("All-time daily peak", value: usage.summary.peakDailyTokens)
                totalRow("Current streak (days)", value: usage.summary.currentStreakDays)
                totalRow("Longest streak (days)", value: usage.summary.longestStreakDays)
            }
            .padding(.top, 6)
        } label: {
            Text(MeterLocalization.text("Account totals"))
                .font(.system(size: 10, weight: .medium))
        }
        Text(MeterLocalization.format("Updated %@", usage.fetchedAt.formatted(.dateTime.month().day().hour().minute().locale(MeterLocalization.locale))))
            .font(.system(size: 9))
            .foregroundStyle(store.analyticsError == nil ? Color.secondary : Color.orange)
    }

    private func metric(title: String, value: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value.map(compact) ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
            Text(MeterLocalization.text("tokens")).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .help(value.map { $0.formatted(.number.locale(MeterLocalization.locale)) } ?? MeterLocalization.text("Not reported"))
        .accessibilityElement(children: .combine)
        .accessibilityValue(value.map { String($0) } ?? MeterLocalization.text("Not reported"))
    }

    private func dailyChart(_ report: AccountUsageReport) -> some View {
        Chart(report.days.filter { $0.tokens != nil }) { day in
            BarMark(
                x: .value(MeterLocalization.text("Day"), day.date, unit: .day),
                y: .value(MeterLocalization.text("Tokens"), day.tokens ?? 0)
            )
            .foregroundStyle(Color.accentColor.opacity(selectedDay == nil || selectedDay == day.day ? 1 : 0.3))
            .cornerRadius(2)
            .accessibilityLabel(day.day)
            .accessibilityValue(String(day.tokens ?? 0))
        }
        .chartXScale(domain: chartDomain(report))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .environment(\.calendar, AccountUsageDay.calendar)
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .frame(height: 100)
        .accessibilityLabel(MeterLocalization.text("Daily account token usage"))
    }

    private func chartDomain(_ report: AccountUsageReport) -> ClosedRange<Date> {
        let start = report.days.first!.date
        let end = report.days.last!.date.addingTimeInterval(86_400)
        return start...end
    }

    private func details(_ report: AccountUsageReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(MeterLocalization.text("Daily details"))
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Picker(MeterLocalization.text("Sort daily usage"), selection: $sort) {
                    ForEach(AccountUsageSort.allCases) { order in Text(order.title).tag(order) }
                }
                .labelsHidden()
                .frame(width: 145)
            }
            HStack(spacing: 8) {
                TextField(MeterLocalization.text("Find date: YYYY-MM-DD"), text: $searchDate)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(MeterLocalization.text("Find usage by date"))
                Toggle(MeterLocalization.text("Active only"), isOn: $onlyActive)
                    .toggleStyle(.checkbox)
                    .fixedSize()
            }
            .font(.system(size: 10))
            let rows = report.details(search: searchDate, onlyActive: onlyActive, sort: sort)
            if rows.isEmpty {
                Text(MeterLocalization.text("No matching daily records."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { day in
                            Button {
                                selectedDay = selectedDay == day.day ? nil : day.day
                            } label: {
                                HStack {
                                    Text(day.day)
                                    Spacer()
                                    Text(day.tokens.map { $0.formatted(.number.locale(MeterLocalization.locale)) } ?? MeterLocalization.text("Not reported"))
                                        .monospacedDigit()
                                }
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(selectedDay == day.day ? Color.accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(MeterLocalization.format("%@: %@ tokens", day.day, day.tokens.map(String.init) ?? MeterLocalization.text("Not reported")))
                        }
                    }
                }
                .frame(height: CGFloat(min(rows.count, 7)) * 25)
            }
            Text(MeterLocalization.text("Filters apply to daily details; the chart and totals show the selected period."))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func totalRow(_ title: String, value: Int64?) -> some View {
        HStack {
            Text(MeterLocalization.text(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value.map { $0.formatted(.number.locale(MeterLocalization.locale)) } ?? "—").monospacedDigit()
        }
        .font(.system(size: 10))
    }

    private func compact(_ count: Int64) -> String {
        if count >= 1_000_000_000 { return String(format: "%.1fB", Double(count) / 1_000_000_000) }
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return String(count)
    }
}
