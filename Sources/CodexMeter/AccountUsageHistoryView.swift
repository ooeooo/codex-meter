import Charts
import CodexMeterCore
import SwiftUI

struct AccountUsageHistoryView: View {
    let now: Date

    init(store: UsageStore, now: Date) {
        self.store = store
        self.now = now
    }
    @ObservedObject var store: UsageStore
    @State private var searchDate = ""
    @State private var onlyActive = false
    @State private var sort: AccountUsageSort = .newest
    @State private var selectedDay: String?
    @State private var detailsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(MeterLocalization.text("Account usage history"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Picker(MeterLocalization.text("Period"), selection: $store.analyticsRange) {
                    ForEach(AccountUsageRange.allCases) { range in Text(range.title).tag(range) }
                }
                .pickerStyle(.segmented)
                .frame(width: 135)
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
                .frame(maxWidth: .infinity, minHeight: 100)
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
            dailyDetailsDisclosure
        }
        .onChange(of: store.analyticsRange) { _ in selectedDay = nil }
    }

    @ViewBuilder
    private func report(_ usage: AccountUsagePayload) -> some View {
        let report = usage.report(range: store.analyticsRange, now: now)
        if report.reportedDays > 0 {
            dailyChart(report)
                .opacity(store.analyticsError == nil ? 1 : 0.5)
        } else {
            Text(MeterLocalization.text(report.hasDailyDetail
                ? "No daily usage was reported for this period."
                : "Codex did not provide daily detail for this account. Account totals are shown below."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 90)
        }
        if now.timeIntervalSince(usage.fetchedAt) > 900 {
            Label(MeterLocalization.text("Account history is out of date. Refresh to update."), systemImage: "clock.badge.exclamationmark")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        }
    }

    private var dailyDetailsDisclosure: some View {
        DisclosureGroup(isExpanded: $detailsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let usage = store.analytics {
                    let report = usage.report(range: store.analyticsRange, now: now)
                    if report.hasDailyDetail {
                        HStack(spacing: 16) {
                            metric(title: MeterLocalization.text(report.reportedDays == report.days.count ? "Period total" : "Reported total"), value: report.totalTokens)
                            Spacer(minLength: 0)
                            metric(title: MeterLocalization.text("Daily peak"), value: report.peakTokens)
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
                        details(report)
                        Divider()
                    }
                    Text(MeterLocalization.text("Account totals"))
                        .font(.system(size: 11, weight: .medium))
                    VStack(spacing: 6) {
                        totalRow("Lifetime tokens", value: usage.summary.lifetimeTokens)
                        totalRow("All-time daily peak", value: usage.summary.peakDailyTokens)
                        totalRow("Current streak (days)", value: usage.summary.currentStreakDays)
                        totalRow("Longest streak (days)", value: usage.summary.longestStreakDays)
                    }
                    Text(MeterLocalization.format("Updated %@", usage.fetchedAt.formatted(.dateTime.month().day().hour().minute().locale(MeterLocalization.locale))))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    Text(MeterLocalization.text("Not reported"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let history = store.quotaHistory, !history.recentChanges.isEmpty {
                    Divider()
                    quotaChanges(history)
                }
                if let error = store.historyError {
                    Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                }
                Text(MeterLocalization.text("Account token history from Codex · dates follow Codex's daily buckets · refreshes every ten minutes"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        } label: {
            Text(MeterLocalization.text("Daily details and account totals"))
                .font(.system(size: 10, weight: .medium))
        }
    }

    private func quotaChanges(_ history: AccountQuotaHistory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MeterLocalization.text("Recent quota changes"))
                .font(.system(size: 11, weight: .medium))
            ForEach(Array(history.recentChanges.prefix(2))) { observation in
                VStack(alignment: .leading, spacing: 3) {
                    Text(observation.payload.fetchedAt.formatted(.dateTime.month().day().hour().minute().locale(MeterLocalization.locale)))
                        .foregroundStyle(.secondary)
                    ForEach(observation.changes.filter { $0.kind != .unchanged && $0.kind != .baseline }) { change in
                        Text(change.summary)
                        if let detail = change.resetDetail { Text(detail).foregroundStyle(.secondary) }
                    }
                    if observation.balanceChanged, let previous = observation.previousCredits,
                       let current = observation.payload.snapshot.credits {
                        Text(MeterLocalization.format("Credits: %@ → %@", previous.displayBalance, current.displayBalance))
                    }
                    if observation.resetCreditsChanged, let previous = observation.previousResetCredits,
                       let current = observation.payload.availableResetCredits {
                        Text(MeterLocalization.format("Banked resets: %d → %d", previous, current))
                    }
                    if observation.hasGap {
                        Text(MeterLocalization.text("Includes an unobserved interval; device and exact usage times are unknown."))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        .chartYScale(domain: 0...max(1, Double(report.peakTokens ?? 0)))
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
                VStack(spacing: 2) {
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
