import Foundation

public enum QuotaWindowKind: String, Codable, Sendable, CaseIterable {
    case primary, secondary

    public func window(in snapshot: RateLimitSnapshot) -> RateLimitWindow? {
        self == .primary ? snapshot.primary : snapshot.secondary
    }
}

public enum QuotaChangeKind: String, Codable, Sendable {
    case baseline, unchanged, decreased, cycleChanged, resetPending, replenished, definitionChanged, unavailable
}

public struct AccountQuotaChange: Equatable, Codable, Sendable, Identifiable {
    public let window: QuotaWindowKind
    public let kind: QuotaChangeKind
    public let previousRemaining: Int?
    public let remaining: Int?
    public let durationMinutes: Int?
    public let previousResetAt: Date?
    public let resetsAt: Date?
    public var id: QuotaWindowKind { window }
    public var displayName: String {
        RateLimitWindow(usedPercent: 0, resetsAt: nil, durationMinutes: durationMinutes).displayName
    }

    /// A net decrease within one observed cycle, never a sum across windows.
    public var decreasePoints: Int? {
        guard kind == .decreased, let previousRemaining, let remaining else { return nil }
        return previousRemaining - remaining
    }

    /// The new cycle's reported usage is known even though total consumption
    /// between two samples spanning a reset cannot be reconstructed.
    public var currentCycleUsedPercent: Int? {
        guard kind == .cycleChanged, let remaining else { return nil }
        return 100 - remaining
    }

    public var resetDetail: String? {
        guard kind == .cycleChanged || kind == .resetPending else { return nil }
        func formatted(_ date: Date) -> String {
            date.formatted(.dateTime.month().day().hour().minute().locale(MeterLocalization.locale))
        }
        if kind == .cycleChanged, let previousResetAt, let resetsAt {
            return MeterLocalization.format("Scheduled reset: %@ · Next reset: %@", formatted(previousResetAt), formatted(resetsAt))
        }
        guard let resetsAt else { return nil }
        return MeterLocalization.format("Scheduled reset: %@", formatted(resetsAt))
    }

    public var summary: String {
        switch kind {
        case .baseline: return MeterLocalization.format("%@: first snapshot", displayName)
        case .unchanged: return MeterLocalization.format("%@: unchanged", displayName)
        case .decreased:
            return MeterLocalization.format("%@: down %d points (%d%% → %d%%)", displayName,
                                            decreasePoints ?? 0, previousRemaining ?? 0, remaining ?? 0)
        case .cycleChanged:
            return MeterLocalization.format("%@: new quota cycle, %d%% used; earlier interval usage unknown", displayName, currentCycleUsedPercent ?? 0)
        case .resetPending:
            return MeterLocalization.format("%@: scheduled reset passed; waiting for updated quota", displayName)
        case .replenished:
            return MeterLocalization.format("%@: quota increased; reset or adjustment", displayName)
        case .definitionChanged:
            return MeterLocalization.format("%@: window changed or unverified; interval usage unknown", displayName)
        case .unavailable:
            return MeterLocalization.format("%@: unavailable", displayName)
        }
    }
}

public struct AccountQuotaObservation: Equatable, Codable, Sendable, Identifiable {
    public let payload: RateLimitPayload
    public let previousFetchedAt: Date?
    public let changes: [AccountQuotaChange]
    public let hasGap: Bool
    public let previousCredits: AccountCredits?
    public let previousResetCredits: Int?
    public var id: Date { payload.fetchedAt }

    public var balanceChanged: Bool {
        guard let previousCredits, let current = payload.snapshot.credits else { return false }
        return previousCredits != current
    }

    public var resetCreditsChanged: Bool {
        guard let previousResetCredits, let current = payload.availableResetCredits else { return false }
        return previousResetCredits != current
    }

    public var hasChanges: Bool {
        changes.contains { change in
            if change.kind == .resetPending {
                // Report crossing the deadline once. Repeated stale responses
                // should not bury the event or look like repeated resets.
                if change.previousRemaining != change.remaining || change.previousResetAt != change.resetsAt { return true }
                guard let previousFetchedAt, let reset = change.resetsAt else { return false }
                return previousFetchedAt < reset && payload.fetchedAt >= reset
            }
            return change.kind != .unchanged && change.kind != .baseline
        }
            || balanceChanged || resetCreditsChanged
    }

    fileprivate init(payload: RateLimitPayload, previous: RateLimitPayload?) {
        self.payload = payload
        previousFetchedAt = previous?.fetchedAt
        hasGap = previous.map { payload.fetchedAt.timeIntervalSince($0.fetchedAt) > 300 } ?? false
        previousCredits = previous?.snapshot.credits
        previousResetCredits = previous?.availableResetCredits
        changes = QuotaWindowKind.allCases.compactMap { slot in
            let old = previous.flatMap { slot.window(in: $0.snapshot) }
            let current = slot.window(in: payload.snapshot)
            guard old != nil || current != nil else { return nil }
            let kind: QuotaChangeKind
            if current == nil {
                kind = .unavailable
            } else if let old, let current, let previous {
                if previous.snapshot.planType != payload.snapshot.planType
                    || previous.snapshot.limitID != payload.snapshot.limitID
                    || old.durationMinutes != current.durationMinutes {
                    kind = .definitionChanged
                } else if let reset = current.resetsAt, reset <= payload.fetchedAt {
                    // A scheduled deadline passing does not prove that the
                    // backend has completed a reset. Never subtract stale data,
                    // even when both percentages and deadlines are unchanged.
                    kind = .resetPending
                } else if old.resetsAt != current.resetsAt {
                    // A moved deadline can also be an early reset. It does not
                    // reveal the exact time or number of intervening resets.
                    if let oldReset = old.resetsAt, let newReset = current.resetsAt,
                       newReset > oldReset, oldReset <= payload.fetchedAt {
                        kind = .cycleChanged
                    } else {
                        kind = .definitionChanged
                    }
                } else if old == current {
                    kind = .unchanged
                } else if current.remainingPercent > old.remainingPercent {
                    kind = .replenished
                } else if old.resetsAt.map({ $0 > payload.fetchedAt }) != true {
                    // A decrease without a trustworthy shared cycle could hide
                    // a reset; retain the snapshot without claiming consumption.
                    kind = .definitionChanged
                } else {
                    kind = .decreased
                }
            } else {
                kind = .baseline
            }
            return AccountQuotaChange(window: slot, kind: kind, previousRemaining: old?.remainingPercent,
                                      remaining: current?.remainingPercent,
                                      durationMinutes: current?.durationMinutes ?? old?.durationMinutes,
                                      previousResetAt: old?.resetsAt, resetsAt: current?.resetsAt)
        }
    }
}

public struct QuotaHistoryPoint: Identifiable, Sendable {
    public let date: Date
    public let remainingPercent: Int
    public let window: QuotaWindowKind
    public let displayName: String
    public let segment: Int
    public var id: String { "\(window.rawValue)-\(date.timeIntervalSince1970)" }
    public var series: String { "\(window.rawValue)-\(segment)" }
}

public struct AccountQuotaHistory: Equatable, Codable, Sendable {
    public static let retention: TimeInterval = 7 * 86_400
    public let accountKey: String
    public private(set) var observations: [AccountQuotaObservation]

    public init(accountKey: String) {
        self.accountKey = accountKey
        observations = []
    }

    public mutating func record(_ payload: RateLimitPayload) {
        let previous = observations.last?.payload
        // Ignore duplicate reads and a clock moving backwards.
        guard previous.map({ payload.fetchedAt > $0.fetchedAt }) ?? true else { return }
        let observation = AccountQuotaObservation(payload: payload, previous: previous)
        let cutoff = payload.fetchedAt.addingTimeInterval(-Self.retention)
        observations.removeAll { $0.payload.fetchedAt < cutoff }
        observations.append(observation)
        // Manual refreshes cannot grow the archive without bound.
        if observations.count > 6_000 { observations.removeFirst(observations.count - 6_000) }
    }

    public var recentChanges: [AccountQuotaObservation] {
        Array(observations.reversed().filter(\.hasChanges).prefix(3))
    }

    public var chartPoints: [QuotaHistoryPoint] {
        var result: [QuotaHistoryPoint] = []
        for slot in QuotaWindowKind.allCases {
            var segment = 0
            for observation in observations {
                let change = observation.changes.first { $0.window == slot }
                if observation.hasGap || (change?.kind != .decreased && change?.kind != .unchanged) {
                    segment += 1
                }
                guard let window = slot.window(in: observation.payload.snapshot) else { continue }
                result.append(QuotaHistoryPoint(date: observation.payload.fetchedAt, remainingPercent: window.remainingPercent,
                                               window: slot, displayName: window.displayName, segment: segment))
            }
        }
        return result
    }

    /// Last observed remaining quota per day. Missing days stay missing.
    public func dailyRemainingPercent(now: Date = Date(), calendar: Calendar = .current) -> [Int?] {
        let slot: QuotaWindowKind = observations.last?.payload.snapshot.secondary == nil ? .primary : .secondary
        let today = calendar.startOfDay(for: now)
        return (-6...0).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return observations.last(where: { $0.payload.fetchedAt >= day && $0.payload.fetchedAt < end })
                .flatMap { slot.window(in: $0.payload.snapshot)?.remainingPercent }
        }
    }
}

/// Stores only numeric account snapshots and an account identity from supported
/// APIs. Never reads credentials or rollout logs. Profiles and accounts are both
/// isolated, including when the default Codex login changes outside this app.
public actor AccountQuotaHistoryStore {
    private struct Archive: Codable {
        var version = 1
        var histories: [String: AccountQuotaHistory] = [:]
    }

    private let directory: URL
    private var archives: [UUID: Archive] = [:]

    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Codex Meter/QuotaHistory", isDirectory: true)) {
        self.directory = directory
    }

    public func record(_ payload: RateLimitPayload, profileID: UUID, accountKey: String) throws -> AccountQuotaHistory {
        let url = directory.appendingPathComponent(profileID.uuidString + ".json")
        var archive: Archive
        if let cached = archives[profileID] {
            archive = cached
        } else if FileManager.default.fileExists(atPath: url.path) {
            archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard archive.version == 1 else { throw CodexClientError.invalidResponse }
        } else {
            archive = Archive()
        }
        var history = archive.histories[accountKey] ?? AccountQuotaHistory(accountKey: accountKey)
        history.record(payload)
        archive.histories[accountKey] = history
        // Bound inactive identities too; never discard the active baseline before
        // comparing it with a new snapshot after a long offline period.
        let cutoff = payload.fetchedAt.addingTimeInterval(-AccountQuotaHistory.retention)
        archive.histories = archive.histories.filter { key, value in
            key == accountKey || (value.observations.last?.payload.fetchedAt ?? .distantPast) >= cutoff
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(archive).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        archives[profileID] = archive
        return history
    }

    public func remove(profileID: UUID) throws {
        let url = directory.appendingPathComponent(profileID.uuidString + ".json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        archives.removeValue(forKey: profileID)
    }
}
