import Charts
import CodexMeterCore
import SwiftUI

struct MeterView: View {
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("usageWindowsExpanded") private var usageWindowsExpanded = true
    @AppStorage("localActivityExpanded") private var localActivityExpanded = true
    @AppStorage("settingsExpanded") private var settingsExpanded = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                Divider()
                content
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
                    await store.refreshActivity()
                }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: store.isRefreshing)
                }
            }
            .buttonStyle(.plain)
            .help(MeterLocalization.text("Refresh usage"))
            .disabled(store.isRefreshing)
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
            if let activity = store.activity {
                Divider()
                DisclosureGroup(isExpanded: $localActivityExpanded) {
                    LocalActivityView(activity: activity, rates: store.costRates, currency: store.currency, totalSavings: store.totalSavings)
                        .padding(.horizontal, -16)
                } label: {
                    SectionLabel(title: MeterLocalization.text("Local activity"), detail: MeterLocalization.format("%@ tokens", compactTokens(activity.total.totalTokens)))
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 0.6)
                }
            } else if let activityError = store.activityError {
                Divider()
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MeterLocalization.text("Local activity unavailable"))
                            .font(.system(size: 11, weight: .medium))
                        Text(activityError)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
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
        } else if store.windows.isEmpty {
            EmptyState(message: store.errorMessage ?? MeterLocalization.text("Usage data is unavailable."), retry: {
                Task { await store.refresh() }
            }, copyDiagnostics: store.copyUsageDiagnostics)
        } else {
            VStack(spacing: 0) {
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
                    : MeterLocalization.text("Reset credits currently available for this account"))
                Divider().padding(.leading, 16)
                ForEach(Array(store.windows.enumerated()), id: \.offset) { index, window in
                    UsageRow(window: window, now: store.payload?.fetchedAt ?? Date())
                    if index < store.windows.count - 1 { Divider().padding(.leading, 16) }
                }
                if let error = store.errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(MeterLocalization.text("Copy Diagnostics"), action: store.copyUsageDiagnostics)
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
                Text(MeterLocalization.text("Currency"))
                    .font(.system(size: 12))
                Spacer()
                Picker(MeterLocalization.text("Currency"), selection: $store.currency) {
                    ForEach(DisplayCurrency.allCases) { currency in
                        Text(currency.code).tag(currency)
                    }
                }
                .labelsHidden()
                .frame(width: 72)
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
            DisclosureGroup(MeterLocalization.text("Fallback USD price for unknown models")) {
                VStack(spacing: 7) {
                    CostRateField(label: MeterLocalization.text("Input"), value: $store.inputRate)
                    CostRateField(label: MeterLocalization.text("Cached input"), value: $store.cachedInputRate)
                    CostRateField(label: MeterLocalization.text("Output"), value: $store.outputRate)
                    Text(MeterLocalization.text("Only used when a model has no bundled official price. USD per million tokens."))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11))
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

    private func compactTokens(_ value: Int64) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
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

private struct LocalActivityView: View {
    let activity: LocalActivitySnapshot
    let rates: LocalCostRates
    let currency: DisplayCurrency
    let totalSavings: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MeterLocalization.text("Local activity"))
                        .font(.system(size: 12, weight: .medium))
                    Text(MeterLocalization.text("Seven days · read from local session logs"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(compactTokens(activity.total.totalTokens))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(MeterLocalization.text("tokens"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Chart(activity.days) { day in
                BarMark(
                    x: .value(MeterLocalization.text("Day"), day.date, unit: .day),
                    y: .value(MeterLocalization.text("Tokens"), day.usage.totalTokens)
                )
                .foregroundStyle(Color.accentColor)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 62)
            .accessibilityLabel(MeterLocalization.text("Seven-day local token activity"))
            .accessibilityValue(accessibilitySummary)

            if !activity.models.isEmpty {
                VStack(spacing: 6) {
                    ForEach(activity.models) { item in
                        HStack(spacing: 8) {
                            Text(item.model)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(modelShare(item))
                                .foregroundStyle(.secondary)
                            Text(modelCost(item))
                                .monospacedDigit()
                                .frame(width: 54, alignment: .trailing)
                        }
                        .font(.system(size: 10))
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            HStack {
                Text(MeterLocalization.format("Today %@", compactTokens(activity.today.totalTokens)))
                Spacer()
                Text(MeterLocalization.format("API-equivalent ≈ %@", formatted(automaticEstimate)))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            Text(MeterLocalization.text("API prices checked 15 Jul 2026 · estimate only"))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            if totalSavings > 0 {
                Text(MeterLocalization.format("Estimated savings vs GPT-5.6 Sol: %@", formatted(totalSavings)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(16)
    }

    private var automaticEstimate: Double {
        let usd = activity.models.reduce(0) { total, item in
            if let price = OpenAIPriceCatalog.price(for: item.model) { return total + price.estimate(item.usage) }
            return total + (rates.isConfigured ? rates.estimate(item.usage) : 0)
        }
        return currency.convertFromUSD(usd)
    }

    private func modelCost(_ item: ModelTokenUsage) -> String {
        if let price = OpenAIPriceCatalog.price(for: item.model) {
            return formatted(currency.convertFromUSD(price.estimate(item.usage)))
        }
        if rates.isConfigured { return formatted(currency.convertFromUSD(rates.estimate(item.usage))) + "*" }
        return MeterLocalization.text("Unpriced")
    }

    private func modelShare(_ item: ModelTokenUsage) -> String {
        guard activity.total.totalTokens > 0 else { return "0%" }
        return "\(Int((Double(item.usage.totalTokens) / Double(activity.total.totalTokens) * 100).rounded()))% · \(compactTokens(item.usage.totalTokens))"
    }

    private func formatted(_ amount: Double) -> String {
        "\(currency.symbol)\(amount.formatted(.number.precision(.fractionLength(2))))"
    }

    private func compactTokens(_ value: Int64) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB", Double(value) / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private var accessibilitySummary: String {
        activity.days.map { day in
            MeterLocalization.format("%@: %lld tokens", day.date.formatted(.dateTime.weekday(.wide).locale(MeterLocalization.locale)), day.usage.totalTokens)
        }.joined(separator: ", ")
    }
}

private struct CostRateField: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
            Text("$/M")
                .foregroundStyle(.secondary)
        }
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
        }
        .frame(maxWidth: .infinity, minHeight: 166)
        .padding(.horizontal, 20)
    }
}
