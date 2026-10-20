import Foundation

public enum CodexClientError: LocalizedError, Equatable {
    case executableNotFound
    case launch(String)
    case disconnected
    case timedOut
    case server(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .executableNotFound: return MeterLocalization.text("Could not find the usage service inside Codex. Select your installed Codex app.")
        case .launch(let message): return MeterLocalization.format("Could not start Codex: %@", message)
        case .disconnected: return MeterLocalization.text("The Codex usage service stopped unexpectedly.")
        case .timedOut: return MeterLocalization.text("Codex did not return usage data in time.")
        case .server(let message): return MeterLocalization.text(message)
        case .invalidResponse: return MeterLocalization.text("Codex returned usage data in an unknown format.")
        }
    }
}

public struct RateLimitWindow: Equatable, Sendable, Codable {
    public let usedPercent: Int
    public let resetsAt: Date?
    public let durationMinutes: Int?

    public init(usedPercent: Int, resetsAt: Date?, durationMinutes: Int?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }

    public var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }

    public var displayName: String {
        guard let durationMinutes, durationMinutes > 0 else { return MeterLocalization.text("Usage window") }
        switch durationMinutes {
        case 300: return MeterLocalization.text("5-hour limit")
        case 1_440: return MeterLocalization.text("Daily limit")
        case 10_080: return MeterLocalization.text("Weekly limit")
        default:
            if durationMinutes.isMultiple(of: 60) {
                return MeterLocalization.format("%lld-hour limit", Int64(durationMinutes / 60))
            }
            return MeterLocalization.format("%lld-minute limit", Int64(durationMinutes))
        }
    }
}

public struct ResetCountdown: Equatable, Sendable {
    public let daysText: String
    public let hoursText: String
    public let accessibilityText: String

    public init(daysText: String, hoursText: String, accessibilityText: String) {
        self.daysText = daysText
        self.hoursText = hoursText
        self.accessibilityText = accessibilityText
    }
}

public enum ResetCountdownFormatter {
    public static func format(until resetDate: Date?, now: Date = Date()) -> ResetCountdown {
        guard let resetDate else {
            return ResetCountdown(daysText: "--", hoursText: "--", accessibilityText: MeterLocalization.text("Reset time unavailable"))
        }

        let secondsRemaining = max(0, Int(resetDate.timeIntervalSince(now)))
        // The menu-bar badge has a fixed 17-point column; retain the compact
        // day/hour suffixes and localize its full accessibility description.
        if secondsRemaining == 0 {
            return ResetCountdown(daysText: "0d", hoursText: "0h", accessibilityText: MeterLocalization.text("Resetting now"))
        }
        if secondsRemaining < 3_600 {
            return ResetCountdown(daysText: "0d", hoursText: "<1h", accessibilityText: MeterLocalization.text("Less than 1 hour until reset"))
        }

        let days = secondsRemaining / 86_400
        let hours = (secondsRemaining % 86_400) / 3_600
        let dayUnit = MeterLocalization.text(days == 1 ? "day" : "days")
        let hourUnit = MeterLocalization.text(hours == 1 ? "hour" : "hours")
        return ResetCountdown(
            daysText: "\(days)d",
            hoursText: "\(hours)h",
            accessibilityText: MeterLocalization.format("%d %@, %d %@ until reset", days, dayUnit, hours, hourUnit)
        )
    }
}

public enum WeeklyPaceSeverity: String, Equatable, Sendable, Codable {
    case belowPace
    case onPace
    case elevated
    case high
    case veryHigh
}

public struct WeeklyPace: Equatable, Sendable, Codable {
    public static let visualLimit = 50.0

    public let actualUsedPercent: Double
    public let expectedUsedPercent: Double
    public let deltaPoints: Double
    public let markerPosition: Double
    public let equivalentTime: TimeInterval
    public let severity: WeeklyPaceSeverity

    public init?(window: RateLimitWindow, now: Date = Date()) {
        guard let durationMinutes = window.durationMinutes,
              durationMinutes >= 9_000,
              let resetsAt = window.resetsAt else { return nil }

        let duration = TimeInterval(durationMinutes * 60)
        guard duration > 0 else { return nil }
        let start = resetsAt.addingTimeInterval(-duration)
        let elapsed = min(max(now.timeIntervalSince(start), 0), duration)
        let expected = elapsed / duration * 100
        let actual = Double(window.usedPercent)
        let delta = actual - expected

        actualUsedPercent = actual
        expectedUsedPercent = expected
        deltaPoints = delta
        markerPosition = min(max(delta / Self.visualLimit, -1), 1)
        equivalentTime = abs(delta) / 100 * duration
        if delta <= -0.5 {
            severity = .belowPace
        } else if delta < 0.5 {
            severity = .onPace
        } else if delta < 15 {
            severity = .elevated
        } else if delta < 30 {
            severity = .high
        } else {
            severity = .veryHigh
        }
    }

    public var summaryText: String {
        guard abs(deltaPoints) >= 0.5 else { return MeterLocalization.text("On pace") }
        let totalHours = max(1, Int(equivalentTime / 3_600))
        let days = totalHours / 24
        let hours = totalHours % 24
        let timeText: String
        if days > 0, hours > 0 {
            timeText = MeterLocalization.format("%dd %dh", days, hours)
        } else if days > 0 {
            timeText = MeterLocalization.format("%dd", days)
        } else {
            timeText = MeterLocalization.format("%dh", hours)
        }
        return MeterLocalization.format(deltaPoints > 0 ? "usage is %@ ahead" : "usage is %@ under pace", timeText)
    }
}

public struct RateLimitSnapshot: Equatable, Sendable, Codable {
    public let limitID: String?
    public let limitName: String?
    public let planType: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let credits: AccountCredits?

    public init(limitID: String?, limitName: String?, planType: String?, primary: RateLimitWindow?, secondary: RateLimitWindow?, credits: AccountCredits? = nil) {
        self.limitID = limitID
        self.limitName = limitName
        self.planType = planType
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
    }

    public var windows: [RateLimitWindow] { [primary, secondary].compactMap { $0 } }
    public var mostConstrainedWindow: RateLimitWindow? {
        windows.min { $0.remainingPercent < $1.remainingPercent }
    }
    public var mostConstrainedRemaining: Int? { mostConstrainedWindow?.remainingPercent }
}

/// The backend reports credits, not a currency amount or an API token balance.
public struct AccountCredits: Equatable, Sendable, Codable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }

    public var displayBalance: String {
        if unlimited { return MeterLocalization.text("Unlimited") }
        if let balance, !balance.isEmpty { return balance }
        return MeterLocalization.text(hasCredits ? "Unavailable" : "No credits")
    }
}

public struct RateLimitPayload: Equatable, Sendable, Codable {
    public let snapshot: RateLimitSnapshot
    public let fetchedAt: Date
    public let availableResetCredits: Int?
    public let accountID: String?

    public init(snapshot: RateLimitSnapshot, fetchedAt: Date, availableResetCredits: Int? = nil, accountID: String? = nil) {
        self.snapshot = snapshot
        self.fetchedAt = fetchedAt
        self.availableResetCredits = availableResetCredits
        self.accountID = accountID
    }
}

public enum RateLimitParser {
    public static func parseResponse(_ data: Data, now: Date = Date()) throws -> RateLimitPayload? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { return nil }

        if let error = root["error"] as? [String: Any] {
            throw CodexClientError.server(error["message"] as? String ?? "Codex returned an unknown error.")
        }

        guard let result = root["result"] as? [String: Any],
              let rawSnapshot = selectSnapshot(from: result) else { return nil }

        let resetCredits = (result["rateLimitResetCredits"] as? [String: Any])
            .flatMap { integer($0["availableCount"]) }
        return RateLimitPayload(
            snapshot: parseSnapshot(rawSnapshot),
            fetchedAt: now,
            availableResetCredits: resetCredits.map { max(0, $0) },
            accountID: result["accountId"] as? String
        )
    }

    public static func parseNotification(_ data: Data, now: Date = Date()) throws -> RateLimitPayload? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              root["method"] as? String == "account/rateLimits/updated",
              let params = root["params"] as? [String: Any],
              let rawSnapshot = params["rateLimits"] as? [String: Any] else { return nil }
        return RateLimitPayload(snapshot: parseSnapshot(rawSnapshot), fetchedAt: now)
    }

    private static func selectSnapshot(from result: [String: Any]) -> [String: Any]? {
        if let byID = result["rateLimitsByLimitId"] as? [String: Any] {
            if let codex = byID["codex"] as? [String: Any] { return codex }
        }
        // App-server chooses the backward-compatible account bucket. A map
        // without "codex" can contain additional model/product quotas; taking
        // its first value would display an arbitrary unrelated allowance.
        return result["rateLimits"] as? [String: Any]
    }

    private static func parseSnapshot(_ raw: [String: Any]) -> RateLimitSnapshot {
        RateLimitSnapshot(
            limitID: raw["limitId"] as? String,
            limitName: raw["limitName"] as? String,
            planType: raw["planType"] as? String,
            primary: parseWindow(raw["primary"]),
            secondary: parseWindow(raw["secondary"]),
            credits: parseCredits(raw["credits"])
        )
    }

    private static func parseCredits(_ value: Any?) -> AccountCredits? {
        guard let raw = value as? [String: Any],
              let hasCredits = raw["hasCredits"] as? Bool,
              let unlimited = raw["unlimited"] as? Bool else { return nil }
        return AccountCredits(hasCredits: hasCredits, unlimited: unlimited, balance: raw["balance"] as? String)
    }

    private static func parseWindow(_ value: Any?) -> RateLimitWindow? {
        guard let raw = value as? [String: Any], let used = integer(raw["usedPercent"]) else { return nil }
        let reset = integer(raw["resetsAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return RateLimitWindow(
            usedPercent: max(0, min(100, used)),
            resetsAt: reset,
            durationMinutes: integer(raw["windowDurationMins"])
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
