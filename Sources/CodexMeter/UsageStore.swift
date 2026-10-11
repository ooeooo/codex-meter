import AppKit
import CodexMeterCore
import Foundation
import ServiceManagement
import UniformTypeIdentifiers
import UserNotifications

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case iconAndPercentage
    case resetAndPercentage
    case percentage
    case icon
    case activity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .iconAndPercentage: return MeterLocalization.text("Icon + percentage")
        case .resetAndPercentage: return MeterLocalization.text("Reset + percentage")
        case .percentage: return MeterLocalization.text("Percentage only")
        case .icon: return MeterLocalization.text("Icon only")
        case .activity: return MeterLocalization.text("Activity chart")
        }
    }
}

struct AccountProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let homePath: String?
    var email: String?

    var homeURL: URL? { homePath.map(URL.init(fileURLWithPath:)) }
    var displayName: String { email ?? (homePath == nil ? MeterLocalization.text("Default") : name) }
}

struct Celebration: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
}

@MainActor
final class UsageStore: ObservableObject {
    private static let defaultAccountID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    @Published private(set) var payload: RateLimitPayload?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var operationError: String?
    @Published private(set) var activity: LocalActivitySnapshot?
    @Published private(set) var activityError: String?
    @Published var language: MeterLanguage {
        didSet {
            MeterLocalization.language = language
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
            renderLocalizedMessages()
        }
    }
    @Published var alertThreshold: Int {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: Self.thresholdKey) }
    }
    @Published private(set) var launchAtLogin = false
    @Published var displayMode: MenuBarDisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey) }
    }
    @Published var inputRate: Double { didSet { persistRates() } }
    @Published var cachedInputRate: Double { didSet { persistRates() } }
    @Published var outputRate: Double { didSet { persistRates() } }
    @Published var currency: DisplayCurrency {
        didSet { UserDefaults.standard.set(currency.rawValue, forKey: Self.currencyKey) }
    }
    @Published private(set) var accounts: [AccountProfile]
    @Published var activeAccountID: UUID {
        didSet { UserDefaults.standard.set(activeAccountID.uuidString, forKey: Self.activeAccountKey) }
    }
    @Published private(set) var celebration: Celebration?
    @Published private(set) var isSwitchingCodexAccount = false
    @Published private(set) var accountSwitchStatus: String?

    private var client: CodexAppServerClient
    private var clientGeneration = UUID()
    private var rediscoverClientOnNextRefresh = false
    private let activityScanner = LocalActivityScanner()
    private let previewMode: Bool
    private var pollingTask: Task<Void, Never>?
    private var activityPollingTask: Task<Void, Never>?
    private var loginTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingNotificationIDs = Set<String>()
    private var lastUsageDiagnostics: String?
    // Retain message sources for language changes; renderers capture local values,
    // rather than this store, so keeping a message cannot create a retain cycle.
    private var errorMessageRenderer: (() -> String?)?
    private var operationErrorRenderer: (() -> String?)?
    private var activityErrorRenderer: (() -> String?)?
    private var accountSwitchStatusRenderer: (() -> String?)?
    private var celebrationRenderer: (() -> Celebration?)?
    private static let languageKey = "appLanguage"
    private static let thresholdKey = "alertThreshold"
    private static let notifiedResetKey = "lastNotifiedReset"
    private static let displayModeKey = "menuBarDisplayMode"
    private static let inputRateKey = "costInputRate"
    private static let cachedInputRateKey = "costCachedInputRate"
    private static let outputRateKey = "costOutputRate"
    private static let currencyKey = "displayCurrency"
    private static let accountsKey = "accountProfiles"
    private static let activeAccountKey = "activeAccountID"
    private static let savingsMilestoneKey = "lastSavingsMilestoneUSD"
    private static let tokenMilestoneKey = "lastTokenMilestone"
    private static let resetMilestoneKey = "lastBankedReset"
    private static let selectedCodexAppKey = "selectedCodexAppPath"

    init(previewMode: Bool = false) {
        let savedLanguage = MeterLanguage(rawValue: UserDefaults.standard.string(forKey: Self.languageKey) ?? "") ?? .system
        MeterLocalization.language = savedLanguage
        self.language = savedLanguage
        let defaultAccount = AccountProfile(id: Self.defaultAccountID, name: "Default", homePath: nil, email: nil)
        let loadedAccounts: [AccountProfile]
        if let data = UserDefaults.standard.data(forKey: Self.accountsKey),
           let decoded = try? JSONDecoder().decode([AccountProfile].self, from: data), !decoded.isEmpty {
            let separateAccounts = decoded.filter { $0.homePath != nil }
            loadedAccounts = [defaultAccount] + separateAccounts
        } else {
            loadedAccounts = [defaultAccount]
        }
        let savedAccount = UserDefaults.standard.string(forKey: Self.activeAccountKey).flatMap(UUID.init(uuidString:))
        let migratedSavedAccount = savedAccount.flatMap { candidate in
            decodedDefaultID(from: UserDefaults.standard.data(forKey: Self.accountsKey)) == candidate
                ? Self.defaultAccountID
                : candidate
        }
        let chosenAccountID = migratedSavedAccount.flatMap { candidate in
            loadedAccounts.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? Self.defaultAccountID
        self.previewMode = previewMode
        self.accounts = loadedAccounts
        self.activeAccountID = chosenAccountID
        self.client = Self.makeClient(codexHome: loadedAccounts.first(where: { $0.id == chosenAccountID })?.homeURL)
        UserDefaults.standard.set(try? JSONEncoder().encode(loadedAccounts), forKey: Self.accountsKey)
        UserDefaults.standard.set(chosenAccountID.uuidString, forKey: Self.activeAccountKey)
        let saved = UserDefaults.standard.integer(forKey: Self.thresholdKey)
        alertThreshold = saved == 0 ? 20 : saved
        displayMode = MenuBarDisplayMode(rawValue: UserDefaults.standard.string(forKey: Self.displayModeKey) ?? "") ?? .iconAndPercentage
        inputRate = UserDefaults.standard.double(forKey: Self.inputRateKey)
        cachedInputRate = UserDefaults.standard.double(forKey: Self.cachedInputRateKey)
        outputRate = UserDefaults.standard.double(forKey: Self.outputRateKey)
        currency = DisplayCurrency(rawValue: UserDefaults.standard.string(forKey: Self.currencyKey) ?? "") ?? .usd
        if previewMode {
            let now = Date()
            payload = RateLimitPayload(
                snapshot: RateLimitSnapshot(
                    limitID: "codex",
                    limitName: "Codex",
                    planType: "plus",
                    primary: RateLimitWindow(usedPercent: 58, resetsAt: now.addingTimeInterval(8_040), durationMinutes: 300),
                    secondary: RateLimitWindow(usedPercent: 32, resetsAt: now.addingTimeInterval(403_200), durationMinutes: 10_080)
                ),
                fetchedAt: now,
                availableResetCredits: 3
            )
            activity = LocalActivitySnapshot(
                days: [8, 5, 6, 3, 7, 4, 9].enumerated().map { offset, millions in
                    DailyTokenUsage(
                        date: Calendar.current.date(byAdding: .day, value: offset - 6, to: Calendar.current.startOfDay(for: now)) ?? now,
                        usage: TokenUsage(inputTokens: Int64(millions) * 900_000, cachedInputTokens: Int64(millions) * 650_000, outputTokens: Int64(millions) * 100_000, totalTokens: Int64(millions) * 1_000_000)
                    )
                },
                models: [
                    ModelTokenUsage(model: "gpt-5.6-sol", usage: TokenUsage(inputTokens: 25_000_000, cachedInputTokens: 18_000_000, outputTokens: 3_000_000, totalTokens: 28_000_000)),
                    ModelTokenUsage(model: "gpt-5.6-terra", usage: TokenUsage(inputTokens: 14_000_000, cachedInputTokens: 10_000_000, outputTokens: 2_000_000, totalTokens: 16_000_000))
                ],
                sampledAt: now,
                filesRead: 12
            )
        }
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    var windows: [RateLimitWindow] { payload?.snapshot.windows ?? [] }
    var activeAccountName: String {
        guard let account = accounts.first(where: { $0.id == activeAccountID }) else { return MeterLocalization.text("Default") }
        return account.homePath == nil ? MeterLocalization.text("Default") : account.name
    }
    var activeAccountDisplayName: String { accounts.first(where: { $0.id == activeAccountID })?.displayName ?? MeterLocalization.text("Default") }
    var canDeleteActiveAccount: Bool { accounts.first(where: { $0.id == activeAccountID })?.homePath != nil }
    var bankedResetCount: Int? { payload?.availableResetCredits }
    var totalSavingsUSD: Double {
        guard let activity else { return 0 }
        guard let baseline = OpenAIPriceCatalog.price(for: "gpt-5.6-sol") else { return 0 }
        return activity.models.reduce(0) { total, item in
            guard let actual = OpenAIPriceCatalog.price(for: item.model) else { return total }
            return total + max(0, baseline.estimate(item.usage) - actual.estimate(item.usage))
        }
    }
    var totalSavings: Double { currency.convertFromUSD(totalSavingsUSD) }
    var menuBarRemaining: Int? {
        guard errorMessage == nil, !isStale else { return nil }
        return payload?.snapshot.mostConstrainedRemaining
    }
    var menuBarWindow: RateLimitWindow? {
        guard errorMessage == nil, !isStale else { return nil }
        return payload?.snapshot.mostConstrainedWindow
    }
    var planLabel: String? {
        payload?.snapshot.planType?.replacingOccurrences(of: "_", with: " ").capitalized
    }
    var costRates: LocalCostRates {
        LocalCostRates(inputPerMillion: inputRate, cachedInputPerMillion: cachedInputRate, outputPerMillion: outputRate)
    }
    var isStale: Bool {
        guard let fetchedAt = payload?.fetchedAt else { return false }
        return Date().timeIntervalSince(fetchedAt) > 180
    }

    private func setErrorMessage(_ render: @autoclosure @escaping () -> String?) {
        errorMessageRenderer = render
        errorMessage = render()
    }

    private func setOperationError(_ render: @autoclosure @escaping () -> String?) {
        operationErrorRenderer = render
        operationError = render()
    }

    private func setActivityError(_ render: @autoclosure @escaping () -> String?) {
        activityErrorRenderer = render
        activityError = render()
    }

    private func setAccountSwitchStatus(_ render: @autoclosure @escaping () -> String?) {
        accountSwitchStatusRenderer = render
        accountSwitchStatus = render()
    }

    private func setCelebration(_ render: @autoclosure @escaping () -> Celebration?) {
        celebrationRenderer = render
        celebration = render()
    }

    private func renderLocalizedMessages() {
        errorMessage = errorMessageRenderer?()
        operationError = operationErrorRenderer?()
        activityError = activityErrorRenderer?()
        accountSwitchStatus = accountSwitchStatusRenderer?()
        celebration = celebrationRenderer?()
    }

    private static func makeClient(codexHome: URL? = nil) -> CodexAppServerClient {
        let selectedApp = selectedCodexAppURL()
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
            .compactMap(\.bundleURL)
        let registeredApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        return CodexAppServerClient(
            codexHome: codexHome,
            appBundleURLs: [selectedApp].compactMap { $0 } + runningApps + [registeredApp].compactMap { $0 }
        )
    }

    private static func selectedCodexAppURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: selectedCodexAppKey) else { return nil }
        let appURL = URL(fileURLWithPath: path, isDirectory: true)
        guard CodexExecutableLocator.desktopExecutableURL(in: appURL) != nil else { return nil }
        return appURL
    }

    private func rebuildCurrentClient() -> CodexAppServerClient {
        let previousClient = client
        let codexHome = accounts.first(where: { $0.id == activeAccountID })?.homeURL
        clientGeneration = UUID()
        client = Self.makeClient(codexHome: codexHome)
        rediscoverClientOnNextRefresh = false
        payload = nil
        setErrorMessage(nil)
        lastUsageDiagnostics = nil
        isRefreshing = false
        return previousClient
    }

    func selectCodexApp() {
        let panel = NSOpenPanel()
        panel.title = MeterLocalization.text("Select Codex App…")
        panel.message = MeterLocalization.text("Choose the installed Codex or ChatGPT app. Codex Meter will use its bundled Codex command-line tool.")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let appURL = selectedURL.standardizedFileURL
        guard CodexExecutableLocator.desktopExecutableURL(in: appURL) != nil else {
            setOperationError(MeterLocalization.text("The selected app is not a supported Codex desktop app with a bundled Codex command-line tool."))
            return
        }

        UserDefaults.standard.set(appURL.path, forKey: Self.selectedCodexAppKey)
        setOperationError(nil)
        pollingTask?.cancel()
        activityPollingTask?.cancel()
        let previousClient = rebuildCurrentClient()
        let nextClient = client
        let generation = clientGeneration
        let accountID = activeAccountID
        Task {
            await previousClient.stop()
            guard isCurrentRequest(client: nextClient, accountID: accountID, generation: generation) else { return }
            start()
        }
    }

    private func isCurrentRequest(client requestClient: CodexAppServerClient, accountID: UUID, generation: UUID) -> Bool {
        client === requestClient && activeAccountID == accountID && clientGeneration == generation
    }

    func start() {
        guard !previewMode else { return }
        pollingTask?.cancel()
        pollingTask = Task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
        activityPollingTask?.cancel()
        activityPollingTask = Task {
            await refreshActivity()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                guard !Task.isCancelled else { break }
                await refreshActivity()
            }
        }
    }

    func refreshActivity() async {
        let generation = clientGeneration
        let accountID = activeAccountID
        do {
            let previous = activity
            let snapshot = try await activityScanner.scan(days: 7)
            guard clientGeneration == generation, activeAccountID == accountID else { return }
            activity = snapshot
            setActivityError(nil)
            detectActivityMilestones(previous: previous, current: activity)
        } catch {
            guard clientGeneration == generation, activeAccountID == accountID else { return }
            activity = nil
            setActivityError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        let previousClient = rediscoverClientOnNextRefresh ? rebuildCurrentClient() : nil
        let requestClient = client
        let generation = clientGeneration
        let accountID = activeAccountID
        isRefreshing = true
        defer {
            if isCurrentRequest(client: requestClient, accountID: accountID, generation: generation) {
                isRefreshing = false
            }
        }
        if let previousClient {
            await previousClient.stop()
            guard isCurrentRequest(client: requestClient, accountID: accountID, generation: generation) else { return }
        }
        do {
            let newPayload = try await requestClient.readRateLimits()
            guard isCurrentRequest(client: requestClient, accountID: accountID, generation: generation) else { return }
            let previous = payload
            payload = newPayload
            setErrorMessage(newPayload.snapshot.windows.isEmpty ? MeterLocalization.text("No Codex rate-limit windows were returned for this account.") : nil)
            if newPayload.snapshot.windows.isEmpty {
                let diagnostics = await requestClient.diagnosticSummary()
                guard isCurrentRequest(client: requestClient, accountID: accountID, generation: generation) else { return }
                lastUsageDiagnostics = diagnostics
                return
            }
            lastUsageDiagnostics = nil
            detectBankedResetMilestone(previous: previous, current: newPayload)
            Task { [weak self] in
                await self?.notifyIfNeeded(newPayload, accountID: accountID, generation: generation)
            }
        } catch {
            guard isCurrentRequest(client: requestClient, accountID: accountID, generation: generation) else { return }
            rediscoverClientOnNextRefresh = (error as? CodexClientError) == .executableNotFound
            setErrorMessage((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            let diagnostics = await requestClient.diagnosticSummary()
            guard isCurrentRequest(client: requestClient, accountID: accountID, generation: generation) else { return }
            lastUsageDiagnostics = diagnostics
            await requestClient.stop()
        }
    }

    func copyUsageDiagnostics() {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let text = [
            MeterLocalization.text("Codex Meter diagnostics"),
            MeterLocalization.format("Version: %@", appVersion),
            MeterLocalization.format("Time: %@", Date().formatted(.dateTime.locale(MeterLocalization.locale))),
            MeterLocalization.format("Active profile: %@ (%@)", activeAccountName, MeterLocalization.text(activeAccountID == Self.defaultAccountID ? "default CODEX_HOME" : "isolated CODEX_HOME")),
            MeterLocalization.format("Last successful refresh: %@", payload?.fetchedAt.formatted(.dateTime.locale(MeterLocalization.locale)) ?? MeterLocalization.text("none")),
            MeterLocalization.format("Usage error: %@", errorMessage ?? MeterLocalization.text("none")),
            lastUsageDiagnostics ?? MeterLocalization.text("Protocol diagnostics: unavailable")
        ].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CodexProcessDiagnostics.redact(text), forType: .string)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        setOperationError(nil)
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            setOperationError(MeterLocalization.format("Launch at login could not be changed: %@", error.localizedDescription))
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openCodex() {
        setOperationError(nil)
        let settingsURL = URL(string: "codex://settings")
        if let selectedApp = Self.selectedCodexAppURL(), let settingsURL {
            NSWorkspace.shared.open([settingsURL], withApplicationAt: selectedApp, configuration: .init()) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.setOperationError(MeterLocalization.format("Codex could not be opened: %@", error.localizedDescription))
                    }
                }
            }
            return
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first {
            running.activate(options: [.activateAllWindows])
            if let settingsURL { _ = NSWorkspace.shared.open(settingsURL) }
            return
        }
        let discoveredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        let fallbackURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        guard let appURL = discoveredURL ?? (FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil) else {
            setOperationError(MeterLocalization.text("Codex is not installed in /Applications."))
            return
        }
        NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.setOperationError(MeterLocalization.format("Codex could not be opened: %@", error.localizedDescription))
                } else if let settingsURL {
                    _ = NSWorkspace.shared.open(settingsURL)
                }
            }
        }
    }

    func requestAccountSwitch(to id: UUID) {
        guard accounts.contains(where: { $0.id == id }), id != activeAccountID else { return }
        guard let profile = accounts.first(where: { $0.id == id }) else { return }

        let alert = NSAlert()
        alert.messageText = MeterLocalization.format("Switch to %@?", profile.displayName)
        alert.informativeText = profile.homeURL == nil
            ? MeterLocalization.text("This is the Codex desktop profile. Codex Meter will switch its usage view to the account currently signed in there.")
            : MeterLocalization.text("Choose whether to switch only Codex Meter, or also sign the Codex desktop app out and open OpenAI's secure browser login for this account.")
        if profile.homeURL == nil {
            alert.addButton(withTitle: MeterLocalization.text("Switch Meter"))
            alert.addButton(withTitle: MeterLocalization.text("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            switchMeterAccount(to: id)
            return
        }
        alert.addButton(withTitle: MeterLocalization.text("Meter + Codex"))
        alert.addButton(withTitle: MeterLocalization.text("Meter Only"))
        alert.addButton(withTitle: MeterLocalization.text("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            switchMeterAccount(to: id)
            Task { await switchCodexDesktopAccount(to: profile) }
        case .alertSecondButtonReturn:
            switchMeterAccount(to: id)
        default:
            return
        }
    }

    private func switchMeterAccount(to id: UUID) {
        guard let profile = accounts.first(where: { $0.id == id }), id != activeAccountID else { return }
        pollingTask?.cancel()
        activityPollingTask?.cancel()
        let previousClient = client
        let generation = UUID()
        clientGeneration = generation
        rediscoverClientOnNextRefresh = false
        activeAccountID = id
        let nextClient = Self.makeClient(codexHome: profile.homeURL)
        client = nextClient
        payload = nil
        activity = nil
        setErrorMessage(nil)
        setOperationError(nil)
        setActivityError(nil)
        lastUsageDiagnostics = nil
        isRefreshing = false
        Task {
            await previousClient.stop()
            guard isCurrentRequest(client: nextClient, accountID: id, generation: generation) else { return }
            start()
        }
    }

    func addAccount() {
        let alert = NSAlert()
        alert.messageText = MeterLocalization.text("Add Codex account")
        alert.informativeText = MeterLocalization.text("Choose a label. Codex Meter will open OpenAI's secure browser sign-in for a private profile on this Mac. Passwords and verification codes stay on OpenAI's page.")
        let field = NSTextField(string: MeterLocalization.text("Work"))
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: MeterLocalization.text("Continue"))
        alert.addButton(withTitle: MeterLocalization.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        setOperationError(nil)
        let id = UUID()
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-meter", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let config = home.appendingPathComponent("config.toml")
            if !FileManager.default.fileExists(atPath: config.path) {
                try Data("cli_auth_credentials_store = \"file\"\n".utf8).write(to: config, options: .atomic)
            }
            let profile = AccountProfile(id: id, name: name, homePath: home.path, email: nil)
            accounts.append(profile)
            persistAccounts()
            startLogin(for: profile)
        } catch {
            setOperationError(MeterLocalization.format("The account profile could not be created: %@", error.localizedDescription))
        }
    }

    func deleteActiveAccount() {
        deleteAccount(id: activeAccountID)
    }

    func deleteAccount(id: UUID) {
        guard let profile = accounts.first(where: { $0.id == id }), let home = profile.homeURL else { return }
        let wasActive = profile.id == activeAccountID
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MeterLocalization.format("Delete %@?", profile.name)
        alert.informativeText = MeterLocalization.text("This removes the locally saved Codex credentials and usage profile from this Mac. It does not delete the OpenAI account.")
        alert.addButton(withTitle: MeterLocalization.text("Delete Account"))
        alert.addButton(withTitle: MeterLocalization.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setOperationError(nil)
        let deletionClient = client
        if wasActive {
            pollingTask?.cancel()
            activityPollingTask?.cancel()
            clientGeneration = UUID()
            rediscoverClientOnNextRefresh = false
            payload = nil
            activity = nil
            setErrorMessage(nil)
            setActivityError(nil)
            lastUsageDiagnostics = nil
            isRefreshing = false
        }
        let deletionGeneration = clientGeneration
        Task {
            if wasActive { await deletionClient.stop() }
            do {
                loginTasks.removeValue(forKey: profile.id)?.cancel()
                try AccountProfileStorage.removeLocalProfile(at: home)
                accounts.removeAll { $0.id == profile.id }
                persistAccounts()
                if wasActive,
                   isCurrentRequest(client: deletionClient, accountID: profile.id, generation: deletionGeneration),
                   let fallback = accounts.first {
                    switchMeterAccount(to: fallback.id)
                }
                setCelebration(Celebration(title: MeterLocalization.text("Account removed"), subtitle: MeterLocalization.text("Local credentials were deleted"), symbol: "trash"))
                dismissCelebration()
            } catch {
                if wasActive, isCurrentRequest(client: deletionClient, accountID: profile.id, generation: deletionGeneration) {
                    clientGeneration = UUID()
                    client = Self.makeClient(codexHome: profile.homeURL)
                    isRefreshing = false
                    start()
                }
                setOperationError(MeterLocalization.format("The local account could not be deleted: %@", error.localizedDescription))
            }
        }
    }

    private func startLogin(for profile: AccountProfile) {
        guard let home = profile.homeURL else { return }
        setOperationError(nil)
        loginTasks[profile.id]?.cancel()
        loginTasks[profile.id] = Task { [weak self] in
            guard let self else { return }
            let loginClient = Self.makeClient(codexHome: home)
            do {
                let login = try await loginClient.startChatGPTLogin()
                guard NSWorkspace.shared.open(login.authorizationURL) else {
                    throw CodexClientError.server("The OpenAI sign-in page could not be opened in your browser.")
                }
                try await loginClient.waitForLogin(id: login.id)
                guard let account = try await loginClient.readAccount(refreshToken: true) else {
                    throw CodexClientError.server("Codex did not report a signed-in account after login.")
                }
                await loginClient.stop()
                self.loginTasks.removeValue(forKey: profile.id)
                if let index = self.accounts.firstIndex(where: { $0.id == profile.id }) {
                    self.accounts[index].email = account.email
                    self.persistAccounts()
                }
                self.switchMeterAccount(to: profile.id)
                self.setCelebration(Celebration(title: MeterLocalization.text("Account ready"), subtitle: MeterLocalization.text("Secure sign-in completed"), symbol: "person.crop.circle.badge.checkmark"))
                self.dismissCelebration()
            } catch is CancellationError {
                await loginClient.stop()
            } catch {
                await loginClient.stop()
                self.loginTasks.removeValue(forKey: profile.id)
                self.accounts.removeAll { $0.id == profile.id }
                self.persistAccounts()
                try? AccountProfileStorage.removeLocalProfile(at: home)
                self.setOperationError(MeterLocalization.format("OpenAI sign-in failed: %@", (error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
            }
        }
    }

    private func persistAccounts() {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: Self.accountsKey)
    }

    private func detectActivityMilestones(previous: LocalActivitySnapshot?, current: LocalActivitySnapshot?) {
        guard !previewMode, previous != nil, let current else { return }
        let newSavings = current.models.reduce(0) { total, item in savingsUSD(for: item) + total }
        let newTokens = current.total.totalTokens
        let savingsStep = max(0, Int(newSavings / 50))
        let savedStep = UserDefaults.standard.integer(forKey: Self.savingsMilestoneKey)
        if savingsStep > savedStep, savingsStep > 0 {
            UserDefaults.standard.set(savingsStep, forKey: Self.savingsMilestoneKey)
            let selectedCurrency = currency
            setCelebration(Celebration(title: MeterLocalization.format("%@ %lld saved", selectedCurrency.code, Int64(selectedCurrency.convertFromUSD(newSavings))), subtitle: MeterLocalization.text("Estimated savings versus GPT-5.6 Sol"), symbol: "sparkles"))
            dismissCelebration()
            return
        }
        let tokenStep = max(0, Int(newTokens / 1_000_000))
        let oldTokenStep = UserDefaults.standard.integer(forKey: Self.tokenMilestoneKey)
        if tokenStep >= 1, tokenStep > oldTokenStep, (tokenStep % 10 == 0 || oldTokenStep == 0) {
            UserDefaults.standard.set(tokenStep, forKey: Self.tokenMilestoneKey)
            setCelebration(Celebration(title: MeterLocalization.text("Token milestone"), subtitle: MeterLocalization.format("You have used %lldM local tokens", Int64(tokenStep)), symbol: "bolt.fill"))
            dismissCelebration()
        }
    }

    private func savingsUSD(for item: ModelTokenUsage) -> Double {
        guard let baseline = OpenAIPriceCatalog.price(for: "gpt-5.6-sol"), let actual = OpenAIPriceCatalog.price(for: item.model) else { return 0 }
        return max(0, baseline.estimate(item.usage) - actual.estimate(item.usage))
    }

    private func detectBankedResetMilestone(previous: RateLimitPayload?, current: RateLimitPayload) {
        guard !previewMode,
              let previousCount = previous?.availableResetCredits,
              let currentCount = current.availableResetCredits,
              currentCount > previousCount else { return }
        let key = "\(activeAccountID.uuidString)-\(currentCount)"
        guard UserDefaults.standard.string(forKey: Self.resetMilestoneKey) != key else { return }
        UserDefaults.standard.set(key, forKey: Self.resetMilestoneKey)
        setCelebration(Celebration(title: MeterLocalization.text("Reset banked"), subtitle: MeterLocalization.format("%lld available for this account", Int64(currentCount)), symbol: "arrow.counterclockwise.circle.fill"))
        dismissCelebration()
    }

    private func switchCodexDesktopAccount(to profile: AccountProfile) async {
        guard !isSwitchingCodexAccount else { return }
        isSwitchingCodexAccount = true
        setAccountSwitchStatus(MeterLocalization.text("Signing Codex out…"))
        setOperationError(nil)

        let desktopClient = Self.makeClient()
        do {
            var expectedEmail = profile.email
            if expectedEmail == nil, let home = profile.homeURL {
                setAccountSwitchStatus(MeterLocalization.format("Checking %@…", profile.name))
                let profileClient = Self.makeClient(codexHome: home)
                if let account = try? await profileClient.readAccount() {
                    expectedEmail = account.email
                    if let index = accounts.firstIndex(where: { $0.id == profile.id }) {
                        accounts[index].email = account.email
                        persistAccounts()
                    }
                }
                await profileClient.stop()
            }
            setAccountSwitchStatus(MeterLocalization.text("Signing Codex out…"))
            try await closeCodexDesktop()
            try await desktopClient.logoutAccount()
            setAccountSwitchStatus(MeterLocalization.text("Waiting for secure OpenAI sign-in…"))
            let login = try await desktopClient.startChatGPTLogin()
            guard NSWorkspace.shared.open(login.authorizationURL) else {
                throw CodexClientError.server("The OpenAI sign-in page could not be opened in your browser.")
            }
            try await desktopClient.waitForLogin(id: login.id)
            guard let signedIn = try await desktopClient.readAccount(refreshToken: true) else {
                throw CodexClientError.server("Codex did not report a signed-in account after login.")
            }
            if let expected = expectedEmail, let actual = signedIn.email,
               expected.caseInsensitiveCompare(actual) != .orderedSame {
                throw AccountMismatchError(actualEmail: actual, expectedEmail: expected)
            }
            await desktopClient.stop()
            setAccountSwitchStatus(nil)
            isSwitchingCodexAccount = false
            openCodex()
            setCelebration(Celebration(
                title: MeterLocalization.text("Codex account switched"),
                subtitle: signedIn.email ?? profile.displayName,
                symbol: "person.crop.circle.badge.checkmark"
            ))
            dismissCelebration()
        } catch {
            await desktopClient.stop()
            setAccountSwitchStatus(nil)
            isSwitchingCodexAccount = false
            openCodex()
            setOperationError(MeterLocalization.format("Codex account switch failed: %@", (error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
        }
    }

    private func closeCodexDesktop() async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        running.forEach { _ = $0.terminate() }
        let deadline = ContinuousClock.now + .seconds(8)
        while NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").contains(where: { !$0.isTerminated }) {
            guard ContinuousClock.now < deadline else {
                throw CodexClientError.server("Codex could not be closed before signing out. Quit Codex and try again.")
            }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    private func dismissCelebration() {
        Task { try? await Task.sleep(for: .seconds(4)); setCelebration(nil) }
    }

    private func notifyIfNeeded(_ payload: RateLimitPayload, accountID: UUID, generation: UUID) async {
        guard clientGeneration == generation, activeAccountID == accountID,
              let constrained = payload.snapshot.windows.min(by: { $0.remainingPercent < $1.remainingPercent }),
              constrained.remainingPercent <= alertThreshold else { return }

        let fallbackBucket = Int(Date().timeIntervalSince1970 / 86_400)
        let resetComponent = constrained.resetsAt.map { Int($0.timeIntervalSince1970) } ?? fallbackBucket
        let resetID = "\(accountID.uuidString)-\(constrained.durationMinutes ?? 0)-\(resetComponent)-\(alertThreshold)"
        guard UserDefaults.standard.string(forKey: Self.notifiedResetKey) != resetID,
              pendingNotificationIDs.insert(resetID).inserted else { return }
        defer { pendingNotificationIDs.remove(resetID) }

        if !previewMode {
            setCelebration(Celebration(title: MeterLocalization.text("Usage running low"), subtitle: MeterLocalization.format("%d%% remains in the tightest window", constrained.remainingPercent), symbol: "exclamationmark.triangle.fill"))
            dismissCelebration()
        }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted, clientGeneration == generation, activeAccountID == accountID else { return }

        let content = UNMutableNotificationContent()
        content.title = MeterLocalization.text("Codex usage is running low")
        content.body = MeterLocalization.format("%d%% remains. %@", constrained.remainingPercent, ResetTimeFormatter.notificationText(for: constrained.resetsAt))
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "codex-meter-low-\(resetID)", content: content, trigger: nil))
        guard clientGeneration == generation, activeAccountID == accountID else { return }
        UserDefaults.standard.set(resetID, forKey: Self.notifiedResetKey)
    }

    private func persistRates() {
        UserDefaults.standard.set(max(0, inputRate), forKey: Self.inputRateKey)
        UserDefaults.standard.set(max(0, cachedInputRate), forKey: Self.cachedInputRateKey)
        UserDefaults.standard.set(max(0, outputRate), forKey: Self.outputRateKey)
    }
}

private struct AccountMismatchError: LocalizedError {
    let actualEmail: String
    let expectedEmail: String

    var errorDescription: String? {
        MeterLocalization.format(
            "Codex signed in as %@, not %@. Sign in again and choose the intended account.",
            actualEmail,
            expectedEmail
        )
    }
}

private func decodedDefaultID(from data: Data?) -> UUID? {
    guard let data,
          let decoded = try? JSONDecoder().decode([AccountProfile].self, from: data) else { return nil }
    return decoded.first(where: { $0.homePath == nil })?.id
}

enum ResetTimeFormatter {
    static func relativeText(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return MeterLocalization.text("Reset time unavailable") }
        if date <= now { return MeterLocalization.text("Resetting now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = MeterLocalization.locale
        return MeterLocalization.format("Resets %@", formatter.localizedString(for: date, relativeTo: now))
    }

    static func absoluteText(for date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(MeterLocalization.locale))
    }

    static func notificationText(for date: Date?) -> String {
        guard let date else { return MeterLocalization.text("The reset time is unavailable.") }
        return MeterLocalization.format("It resets %@.", date.formatted(.dateTime.hour().minute().locale(MeterLocalization.locale)))
    }
}
