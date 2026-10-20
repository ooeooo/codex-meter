import Foundation

public enum AccountUsageError: LocalizedError, Equatable, Sendable {
    case unsupported
    case invalidResponse
    case unverifiedAccount
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return MeterLocalization.text("This Codex version does not provide account analytics. Update Codex and retry, or open Usage and billing → Analytics in Codex settings.")
        case .invalidResponse:
            return MeterLocalization.text("Codex returned account analytics in an unknown or inconsistent format.")
        case .unverifiedAccount:
            return MeterLocalization.text("The signed-in account could not be verified. Retry after signing in to Codex.")
        case .server(let message): return message
        }
    }
}

public enum AccountUsageRange: Int, CaseIterable, Identifiable, Sendable {
    case week = 7, month = 30
    public var id: Int { rawValue }
    public var title: String { MeterLocalization.format("%d days", rawValue) }
}

public enum AccountUsageSort: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest, mostTokens, leastTokens
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .newest: return MeterLocalization.text("Newest first")
        case .oldest: return MeterLocalization.text("Oldest first")
        case .mostTokens: return MeterLocalization.text("Most tokens first")
        case .leastTokens: return MeterLocalization.text("Fewest tokens first")
        }
    }
}

public struct AccountUsageSummary: Codable, Equatable, Sendable {
    public let lifetimeTokens: Int64?
    public let peakDailyTokens: Int64?
    public let longestRunningTurnSec: Int64?
    public let currentStreakDays: Int64?
    public let longestStreakDays: Int64?

    public init(lifetimeTokens: Int64? = nil, peakDailyTokens: Int64? = nil,
                longestRunningTurnSec: Int64? = nil, currentStreakDays: Int64? = nil, longestStreakDays: Int64? = nil) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSec = longestRunningTurnSec
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
    }
}

/// The server's day label is preserved without shifting it into another time
/// zone. A UTC date is only a stable plotting coordinate for that calendar label.
public struct AccountUsageDay: Codable, Equatable, Sendable, Identifiable {
    public let day: String
    public let tokens: Int64?
    public var id: String { day }
    public var date: Date { Self.date(for: day)! }

    public init?(day: String, tokens: Int64?) {
        guard Self.date(for: day) != nil, tokens.map({ $0 >= 0 }) ?? true else { return nil }
        self.day = day
        self.tokens = tokens
    }

    private enum CodingKeys: String, CodingKey { case day, tokens }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let day = try container.decode(String.self, forKey: .day)
        let tokens = try container.decodeIfPresent(Int64.self, forKey: .tokens)
        guard let valid = Self(day: day, tokens: tokens) else { throw AccountUsageError.invalidResponse }
        self = valid
    }

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public static func date(for day: String) -> Date? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard day.count == 10, parts.count == 3, parts[0].count == 4,
              parts[1].count == 2, parts[2].count == 2,
              day.utf8.allSatisfy({ (48...57).contains($0) || $0 == 45 }),
              let year = Int(parts[0]), (1...9_999).contains(year),
              let month = Int(parts[1]), let date = Int(parts[2]),
              let result = calendar.date(from: DateComponents(year: year, month: month, day: date)) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: result)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == date else { return nil }
        return result
    }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

public struct AccountUsagePayload: Equatable, Sendable {
    public let summary: AccountUsageSummary
    /// nil means daily detail was not provided; an empty array means no rows.
    public let days: [AccountUsageDay]?
    public let fetchedAt: Date

    public init(summary: AccountUsageSummary, days: [AccountUsageDay]?, fetchedAt: Date) {
        self.summary = summary
        self.days = days
        self.fetchedAt = fetchedAt
    }

    public func report(range: AccountUsageRange, now: Date = Date(), calendar: Calendar = .current) -> AccountUsageReport {
        // Use Gregorian labels in the user's current time zone for the range,
        // while keeping each backend day label intact for display and matching.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        let today = AccountUsageDay.key(for: now, calendar: local)
        let end = AccountUsageDay.date(for: today)!
        let reported = Dictionary((days ?? []).map { ($0.day, $0.tokens) }, uniquingKeysWith: { first, _ in first })
        let rows = (0..<range.rawValue).reversed().compactMap { offset -> AccountUsageDay? in
            guard let date = AccountUsageDay.calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let key = AccountUsageDay.key(for: date, calendar: AccountUsageDay.calendar)
            return AccountUsageDay(day: key, tokens: reported[key] ?? nil)
        }
        return AccountUsageReport(days: rows, hasDailyDetail: days != nil)
    }
}

public struct AccountUsageReport: Equatable, Sendable {
    public let days: [AccountUsageDay]
    public let hasDailyDetail: Bool
    public var reportedDays: Int { days.filter { $0.tokens != nil }.count }
    public var activeDays: Int { days.filter { ($0.tokens ?? 0) > 0 }.count }
    public var peakTokens: Int64? { days.compactMap(\.tokens).max() }
    public var totalTokens: Int64? {
        guard reportedDays > 0 else { return nil }
        var total: Int64 = 0
        for count in days.compactMap(\.tokens) {
            let next = total.addingReportingOverflow(count)
            guard !next.overflow else { return nil }
            total = next.partialValue
        }
        return total
    }

    /// Detail-table filters do not change period-wide summary/chart values.
    public func details(search: String = "", onlyActive: Bool = false, sort: AccountUsageSort = .newest) -> [AccountUsageDay] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return days.filter { day in
            (query.isEmpty || day.day.contains(query)) && (!onlyActive || (day.tokens ?? 0) > 0)
        }.sorted { lhs, rhs in
            switch sort {
            case .newest: return lhs.day > rhs.day
            case .oldest: return lhs.day < rhs.day
            case .mostTokens, .leastTokens:
                if lhs.tokens == rhs.tokens { return lhs.day > rhs.day }
                guard let left = lhs.tokens else { return false }
                guard let right = rhs.tokens else { return true }
                return sort == .mostTokens ? left > right : left < right
            }
        }
    }
}

public enum AccountUsageParser {
    private struct Count: Decodable {
        let value: Int64
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int64.self), number >= 0 {
                value = number
            } else if let string = try? container.decode(String.self), !string.isEmpty,
                      string.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int64(string) {
                value = number
            } else {
                throw AccountUsageError.invalidResponse
            }
        }
    }
    private struct Summary: Decodable {
        let lifetimeTokens: Count?
        let peakDailyTokens: Count?
        let longestRunningTurnSec: Count?
        let currentStreakDays: Count?
        let longestStreakDays: Count?
    }
    private struct Day: Decodable { let startDate: String; let tokens: Count }
    private struct Result: Decodable { let summary: Summary; let dailyUsageBuckets: [Day]? }
    private struct RPCError: Decodable { let code: Int; let message: String }
    private struct Response: Decodable { let result: Result?; let error: RPCError? }

    public static func parseResponse(_ data: Data, now: Date = Date()) throws -> AccountUsagePayload {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AccountUsageError.invalidResponse }
        if let error = response.error {
            if error.code == -32601 { throw AccountUsageError.unsupported }
            throw AccountUsageError.server(error.message)
        }
        guard let result = response.result else { throw AccountUsageError.invalidResponse }
        var counts: [String: Int64] = [:]
        for row in result.dailyUsageBuckets ?? [] {
            guard let key = dayKey(row.startDate),
                  let day = AccountUsageDay(day: key, tokens: row.tokens.value),
                  counts[day.day].map({ $0 == row.tokens.value }) ?? true else { throw AccountUsageError.invalidResponse }
            counts[day.day] = row.tokens.value
        }
        let summary = result.summary
        return AccountUsagePayload(
            summary: AccountUsageSummary(lifetimeTokens: summary.lifetimeTokens?.value, peakDailyTokens: summary.peakDailyTokens?.value,
                longestRunningTurnSec: summary.longestRunningTurnSec?.value, currentStreakDays: summary.currentStreakDays?.value,
                longestStreakDays: summary.longestStreakDays?.value),
            days: result.dailyUsageBuckets.map { _ in counts.keys.sorted().compactMap { AccountUsageDay(day: $0, tokens: counts[$0]) } },
            fetchedAt: now)
    }

    private static func dayKey(_ raw: String) -> String? {
        if AccountUsageDay.date(for: raw) != nil { return raw }
        // Some server versions serialize the day boundary as an ISO timestamp.
        // Validate the complete value and preserve its source calendar label.
        let key = String(raw.prefix(10))
        guard AccountUsageDay.date(for: key) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        if formatter.date(from: raw) != nil { return key }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: raw) == nil ? nil : key
    }
}
