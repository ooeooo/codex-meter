import Charts
import CodexMeterCore
import SwiftUI

struct MeterView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("usageWindowsExpanded") private var usageWindowsExpanded = true
    @AppStorage("quotaHistoryExpanded") private var quotaHistoryExpanded = true
    @AppStorage("settingsExpanded") private var settingsExpanded = false
    @State private var showingAnalytics = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                Divider()
                Picker(MeterLocalization.text("View"), selection: $showingAnalytics) {
                    Text(MeterLocalization.text("Overview")).tag(false)
                    Text(MeterLocalization.text("Analytics")).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                if showingAnalytics {
                    AccountUsageAnalyticsView(store: store)
                        .id(store.activeAccountID)
                } else {
                    content
                }
                Divider()
                settings
            }
            if let celebration = store.celebration {
                CelebrationBanner(celebration: celebration)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .id(store.language)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.celebration)
        .environment(\.locale, MeterLocalization.locale)
        .frame(width: 348)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.42), lineWidth: 0.75)
        }
        .onChange(of: store.operationError) { error in
            if error != nil { settingsExpanded = true }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.14))
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Meter")
                    .font(.system(size: 15, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            accountMenu
            Button {
                Task {
                    await store.refresh()
                    await store.refreshAnalytics(force: true)
                }
            } label: {
                if store.isRefreshing || store.isLoadingAnalytics {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: store.isRefreshing)
                }
            }
            .buttonStyle(.plain)
            .help(MeterLocalization.text("Refresh usage"))
            .disabled(store.isRefreshing || store.isLoadingAnalytics)
            .accessibilityLabel(MeterLocalization.text("Refresh Codex usage"))
        }
        .padding(16)
    }

    private var accountMenu: some View {
        Menu {
            Section(MeterLocalization.text("Use account")) {
                ForEach(store.accounts) { account in
                    Button {
                        store.requestAccountSwitch(to: account.id)
                    } label: {
                        if account.id == store.activeAccountID {
                            Label(account.displayName, systemImage: "checkmark")
                        } else {
                            Text(account.displayName)
                        }
                    }
                    .disabled(account.id == store.activeAccountID)
                }
            }
            Divider()
            Button(MeterLocalization.text("Add account…"), systemImage: "person.badge.plus") {
                store.addAccount()
            }
            let removableAccounts = store.accounts.filter { $0.homePath != nil }
            if !removableAccounts.isEmpty {
                Menu(MeterLocalization.text("Delete account"), systemImage: "trash") {
                    ForEach(removableAccounts) { account in
                        Button(account.displayName, role: .destructive) {
                            store.deleteAccount(id: account.id)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                Text(store.activeAccountDisplayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: 112)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(store.isSwitchingCodexAccount)
        .help(MeterLocalization.text("Switch Codex account"))
        .accessibilityLabel(MeterLocalization.format("Current account: %@. Open account switcher", store.activeAccountDisplayName))
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            DisclosureGroup(isExpanded: $usageWindowsExpanded) {
                quotaContent
            } label: {
                SectionLabel(title: MeterLocalization.text("Usage windows"), detail: store.activeAccountName)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
            }
            Divider()
            DisclosureGroup(isExpanded: $quotaHistoryExpanded) {
                if let history = store.quotaHistory {
                    AccountQuotaHistoryView(history: history)
                        .padding(.top, 10)
                } else {
                    Text(MeterLocalization.text("History starts with the first successful account quota read."))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
                if let error = store.historyError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            } label: {
                SectionLabel(title: MeterLocalization.text("Account quota history"), detail: MeterLocalization.text("All devices"))
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
            }
        }
    }

    @ViewBuilder
    private var quotaContent: some View {
        if store.payload == nil && store.isRefreshing {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(MeterLocalization.text("Checking Codex usage…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 148)
        } else if store.windows.isEmpty && store.payload?.snapshot.credits == nil && store.bankedResetCount == nil {
            EmptyState(message: store.errorMessage ?? MeterLocalization.text("Usage data is unavailable."), retry: {
                Task { await store.refresh() }
            }, copyDiagnostics: store.copyUsageDiagnostics, selectCodexApp: store.selectCodexApp)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .foregroundStyle(Color.accentColor)
                    Text(MeterLocalization.text("Credits balance"))
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text(store.payload?.snapshot.credits?.displayBalance ?? MeterLocalization.text("Unavailable"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .help(MeterLocalization.text("Account credits returned by Codex, separate from included quota. No currency conversion is applied."))
                Divider().padding(.leading, 16)
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .foregroundStyle(Color.accentColor)
                    Text(MeterLocalization.text("Banked resets"))
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text(store.bankedResetCount.map(String.init) ?? "—")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .help(store.bankedResetCount == nil
                    ? MeterLocalization.text("OpenAI did not return a banked reset count for this account")
                    : MeterLocalization.text("Available reset counts can change through grants, use or expiry; a count change does not prove a reset."))
                Divider().padding(.leading, 16)
                ForEach(Array(store.windows.enumerated()), id: \.offset) { index, window in
                    UsageRow(window: window, now: store.payload?.fetchedAt ?? Date())
                    if index < store.windows.count - 1 { Divider().padding(.leading, 16) }
                }
                if let error = store.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 12) {
                            Button(MeterLocalization.text("Select Codex App…"), action: store.selectCodexApp)
                            Button(MeterLocalization.text("Copy Diagnostics"), action: store.copyUsageDiagnostics)
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var settings: some View {
        DisclosureGroup(isExpanded: $settingsExpanded) {
            footer
        } label: {
            SectionLabel(title: MeterLocalization.text("Settings"), detail: MeterLocalization.text("Display, alerts and accounts"))
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = store.operationError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MeterLocalization.text("Operation failed"))
                            .font(.system(size: 11, weight: .medium))
                        Text(error)
                            .font(.system(size: 10))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MeterLocalization.text("Active account"))
                        .font(.system(size: 12))
                    Text(store.activeAccountDisplayName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(MeterLocalization.text("Add…")) { store.addAccount() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Button(MeterLocalization.text("Delete…")) { store.deleteActiveAccount() }
                    .buttonStyle(.plain)
                    .foregroundStyle(store.canDeleteActiveAccount ? Color.red : Color.secondary)
                    .disabled(!store.canDeleteActiveAccount)
            }
            if let status = store.accountSwitchStatus {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(MeterLocalization.text("Desktop switching uses OpenAI's secure sign-in."))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(MeterLocalization.text("Open Codex…")) { store.openCodex() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            HStack {
                Text(MeterLocalization.text("Menu bar"))
                    .font(.system(size: 12))
                Spacer()
                Picker(MeterLocalization.text("Menu bar display"), selection: $store.displayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            HStack {
                Text(MeterLocalization.text("Language"))
                    .font(.system(size: 12))
                Spacer()
                Picker(MeterLocalization.text("Language"), selection: $store.language) {
                    ForEach(MeterLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            HStack {
                Text(MeterLocalization.text("Low-usage alert"))
                    .font(.system(size: 12))
                Spacer()
                Picker(MeterLocalization.text("Low-usage alert"), selection: $store.alertThreshold) {
                    Text("10%").tag(10)
                    Text("20%").tag(20)
                    Text("30%").tag(30)
                }
                .labelsHidden()
                .frame(width: 72)
            }
            Toggle(MeterLocalization.text("Launch at login"), isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .font(.system(size: 12))
            HStack {
                Button(MeterLocalization.text("Open Codex")) { store.openCodex() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button(MeterLocalization.text("Quit")) { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(16)
    }

    private var headerSubtitle: String {
        if store.isStale { return MeterLocalization.text("Last update is stale") }
        if let date = store.payload?.fetchedAt {
            return MeterLocalization.format("Updated %@", date.formatted(.dateTime.hour().minute().locale(MeterLocalization.locale))) + (store.planLabel.map { " · \($0)" } ?? "")
        }
        return MeterLocalization.text("Signed in through the Codex app")
    }
}

private struct SectionLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private struct CelebrationBanner: View {
    let celebration: Celebration

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: celebration.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(celebration.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(celebration.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.accentColor.opacity(0.35)))
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

private struct AccountQuotaHistoryView: View {
    let history: AccountQuotaHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MeterLocalization.text("Seven days · checks every two minutes"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if history.chartPoints.isEmpty {
                Text(MeterLocalization.text("Percentage quota was not provided for this account."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                quotaChart
            }

            if history.observations.count == 1 {
                Text(MeterLocalization.text("First snapshot saved. Changes will appear after the next read."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(history.recentChanges.prefix(2))) { observation in
                changeRow(observation)
            }
            Text(MeterLocalization.text("Account snapshots include cloud and other devices. Gaps and resets break the line; usage across resets cannot be recovered."))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quotaChart: some View {
        Chart(history.chartPoints) { point in
            LineMark(
                x: .value(MeterLocalization.text("Time"), point.date),
                y: .value(MeterLocalization.text("Remaining quota"), point.remainingPercent),
                series: .value("Series", point.series)
            )
            .foregroundStyle(by: .value(MeterLocalization.text("Usage window"), point.displayName))
            .symbol(.circle)
            .symbolSize(6)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisValueLabel {
                    if let percent = value.as(Int.self) { Text("\(percent)%") }
                }
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .chartForegroundStyleScale(range: [Color.accentColor, Color.orange])
        .frame(height: 90)
        .accessibilityLabel(MeterLocalization.text("Account remaining quota history"))
    }

    private func changeRow(_ observation: AccountQuotaObservation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(intervalText(observation))
                .foregroundStyle(.secondary)
            ForEach(observation.changes.filter { $0.kind != .unchanged && $0.kind != .baseline }) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.summary)
                    if let detail = change.resetDetail {
                        Text(detail)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
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

    private func intervalText(_ observation: AccountQuotaObservation) -> String {
        let end = observation.payload.fetchedAt.formatted(.dateTime.month().day().hour().minute().locale(MeterLocalization.locale))
        guard let start = observation.previousFetchedAt else { return end }
        return start.formatted(.dateTime.month().day().hour().minute().locale(MeterLocalization.locale)) + " → " + end
    }
}

private struct UsageRow: View {
    let window: RateLimitWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(window.displayName)
                            .font(.system(size: 12, weight: .medium))
                        if let warningText {
                            Text(warningText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(meterColor)
                        }
                    }
                    Text(ResetTimeFormatter.relativeText(for: window.resetsAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(window.remainingPercent)%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(MeterLocalization.text("remaining"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let absoluteReset = ResetTimeFormatter.absoluteText(for: window.resetsAt) {
                        Text(absoluteReset)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(MeterLocalization.format("%d percent remaining", window.remainingPercent))
            }

            UsageProgressBar(remainingPercent: window.remainingPercent, color: meterColor)
                .animation(.easeInOut(duration: 0.45), value: window.remainingPercent)
                .accessibilityLabel(window.displayName)
                .accessibilityValue([
                    MeterLocalization.format("%d percent remaining.", window.remainingPercent),
                    ResetTimeFormatter.relativeText(for: window.resetsAt),
                    ResetTimeFormatter.absoluteText(for: window.resetsAt)
                ].compactMap { $0 }.joined(separator: " "))

            if let pace = WeeklyPace(window: window, now: now) {
                Divider()
                WeeklyPaceView(pace: pace)
            }
        }
        .padding(16)
    }

    private var meterColor: Color {
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 25 { return .orange }
        return .accentColor
    }

    private var warningText: String? {
        if window.remainingPercent <= 10 { return MeterLocalization.text("Nearly exhausted") }
        if window.remainingPercent <= 25 { return MeterLocalization.text("Running low") }
        return nil
    }
}

private struct UsageProgressBar: View {
    let remainingPercent: Int
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18)).frame(height: 8)
                Capsule()
                    .fill(color)
                    .frame(width: width * CGFloat(remainingPercent) / 100, height: 8)
                ForEach(0...8, id: \.self) { index in
                    Rectangle()
                        .fill(Color.primary.opacity(index.isMultiple(of: 2) ? 0.24 : 0.12))
                        .frame(width: 1, height: index.isMultiple(of: 2) ? 14 : 10)
                        .position(x: min(max(width * CGFloat(index) / 8, 0.5), width - 0.5), y: 7)
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }
}

private struct WeeklyPaceView: View {
    let pace: WeeklyPace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(MeterLocalization.text("Weekly pace"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(pace.summaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PacePalette.color(for: pace.deltaPoints))
            }
            Text(MeterLocalization.format("%d%% used · %d%% expected by now", rounded(pace.actualUsedPercent), rounded(pace.expectedUsedPercent)))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            PaceBar(pace: pace)
            HStack {
                Text("−50%")
                Spacer()
                Text(MeterLocalization.text("On pace"))
                Spacer()
                Text("+50%")
            }
            .font(.system(size: 8))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MeterLocalization.text("Weekly pace"))
        .accessibilityValue(MeterLocalization.format("%@. %d percent used; %d percent expected by now.", pace.summaryText, rounded(pace.actualUsedPercent), rounded(pace.expectedUsedPercent)))
    }

    private func rounded(_ value: Double) -> Int { Int(value.rounded()) }
}

private struct PaceBar: View {
    let pace: WeeklyPace

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let center = width / 2
            let marker = width * CGFloat((pace.markerPosition + 1) / 2)
            let color = PacePalette.color(for: pace.deltaPoints)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22)).frame(height: 8)
                Capsule()
                    .fill(color)
                    .frame(width: abs(marker - center), height: 8)
                    .position(x: (marker + center) / 2, y: 9)
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1, height: 13)
                    .position(x: center, y: 5.5)
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(Circle().stroke(color, lineWidth: 3))
                    .frame(width: 13, height: 13)
                    .position(x: marker, y: 9)
            }
            .frame(height: 18)
        }
        .frame(height: 18)
    }
}

private enum PacePalette {
    static func color(for delta: Double) -> Color {
        guard delta > 0 else { return Color(nsColor: .systemGreen) }
        let stops: [(Double, NSColor)] = [
            (0, .systemGreen),
            (12.5, .systemYellow),
            (25, .systemOrange),
            (37.5, .systemRed),
            (50, NSColor(calibratedRed: 0.55, green: 0.02, blue: 0.04, alpha: 1))
        ]
        let clamped = min(delta, 50)
        for index in 1..<stops.count where clamped <= stops[index].0 {
            let lower = stops[index - 1]
            let upper = stops[index]
            let fraction = (clamped - lower.0) / (upper.0 - lower.0)
            return Color(nsColor: lower.1.blended(withFraction: fraction, of: upper.1) ?? upper.1)
        }
        return Color(nsColor: stops.last!.1)
    }
}

private struct EmptyState: View {
    let message: String
    let retry: () -> Void
    let copyDiagnostics: () -> Void
    let selectCodexApp: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(MeterLocalization.text("Usage unavailable"))
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            HStack(spacing: 10) {
                Button(MeterLocalization.text("Try again"), action: retry)
                Button(MeterLocalization.text("Copy Diagnostics"), action: copyDiagnostics)
            }
            .controlSize(.small)
            Button(MeterLocalization.text("Select Codex App…"), action: selectCodexApp)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 166)
        .padding(.horizontal, 20)
    }
}
