import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
struct AccountUsageCheck {
    static func parse(_ json: String) throws -> AccountUsagePayload {
        try AccountUsageParser.parseResponse(Data(json.utf8), now: Date(timeIntervalSince1970: 1))
    }

    static func main() throws {
        MeterLocalization.language = .english
        let payload = try parse(#"{"id":4,"result":{"summary":{"lifetimeTokens":9007199254740993,"peakDailyTokens":"1000000","longestRunningTurnSec":15,"currentStreakDays":3,"longestStreakDays":5},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":200},{"startDate":"2026-10-14","tokens":"100"},{"startDate":"2026-10-13","tokens":9000},{"startDate":"2026-10-19","tokens":0},{"startDate":"2026-09-21","tokens":400},{"startDate":"2026-09-20","tokens":9000},{"startDate":"2026-10-21","tokens":9000}]}}"#)
        precondition(payload.summary.lifetimeTokens == 9_007_199_254_740_993)
        precondition(payload.summary.peakDailyTokens == 1_000_000)
        precondition(payload.fetchedAt == Date(timeIntervalSince1970: 1))
        precondition(payload.days?.map(\.day) == payload.days?.map(\.day).sorted())
        let now = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
        let utc = AccountUsageDay.calendar
        let week = payload.report(range: .week, now: now, calendar: utc)
        precondition(week.days.count == 7 && week.days.first?.day == "2026-10-14" && week.days.last?.day == "2026-10-20")
        precondition(week.totalTokens == 300 && week.peakTokens == 200)
        precondition(week.reportedDays == 3 && week.activeDays == 2)
        precondition(week.days.first(where: { $0.day == "2026-10-19" })?.tokens == 0)
        precondition(week.days.first(where: { $0.day == "2026-10-18" })?.tokens == nil)
        let month = payload.report(range: .month, now: now, calendar: utc)
        precondition(month.days.count == 30 && month.days.first?.day == "2026-09-21")
        precondition(month.totalTokens == 9_700) // Excludes both Sep 20 and tomorrow.
        precondition(month.reportedDays == 5)

        precondition(week.details(search: " 2026-10-20 ").map(\.tokens) == [200])
        precondition(week.details(search: "2026-09").isEmpty)
        precondition(week.details(onlyActive: true).count == 2)
        precondition(week.details(sort: .oldest).first?.day == "2026-10-14")
        precondition(week.details(sort: .newest).first?.day == "2026-10-20")
        precondition(week.details(sort: .mostTokens).prefix(3).map(\.tokens) == [200, 100, 0])
        precondition(week.details(sort: .leastTokens).prefix(3).map(\.tokens) == [0, 100, 200])
        precondition(week.details(sort: .mostTokens).suffix(4).allSatisfy { $0.tokens == nil })
        precondition(week.totalTokens == 300) // Table filters don't change range totals.

        let absent = try parse(#"{"result":{"summary":{},"dailyUsageBuckets":null}}"#)
        precondition(absent.days == nil && absent.summary.lifetimeTokens == nil)
        let absentReport = absent.report(range: .week, now: now, calendar: utc)
        precondition(!absentReport.hasDailyDetail && absentReport.totalTokens == nil)
        let empty = try parse(#"{"result":{"summary":{},"dailyUsageBuckets":[]}}"#)
        let emptyReport = empty.report(range: .week, now: now, calendar: utc)
        precondition(emptyReport.hasDailyDetail && emptyReport.reportedDays == 0 && emptyReport.totalTokens == nil)
        let zero = try parse(#"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":0}]}}"#)
        precondition(zero.report(range: .week, now: now, calendar: utc).totalTokens == 0)

        let duplicates = try parse(#"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":42},{"startDate":"2026-10-20","tokens":42}]}}"#)
        precondition(duplicates.days?.count == 1)
        precondition(duplicates.report(range: .week, now: now, calendar: utc).totalTokens == 42)
        for invalid in [
            #"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":1},{"startDate":"2026-10-20","tokens":2}]}}"#,
            #"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-02-30","tokens":1}]}}"#,
            #"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":-1}]}}"#,
            #"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":true}]}}"#,
            #"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":1.5}]}}"#,
            #"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":"9223372036854775808"}]}}"#,
            #"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":null}]}}"#,
            #"{"result":{"summary":{"lifetimeTokens":-1}}}"#,
            #"{"result":{"summary":null}}"#,
            #"{"result":{}}"#
        ] {
            do { _ = try parse(invalid); preconditionFailure("Invalid usage accepted") }
            catch let error as AccountUsageError { precondition(error == .invalidResponse) }
        }
        for (raw, expected) in [
            (#"{"error":{"code":-32601,"message":"Method not found"}}"#, AccountUsageError.unsupported),
            (#"{"error":{"code":-32000,"message":"Sign in required"}}"#, AccountUsageError.server("Sign in required"))
        ] {
            do { _ = try parse(raw); preconditionFailure("RPC error accepted") }
            catch let error as AccountUsageError { precondition(error == expected) }
        }

        let timestamp = try parse(#"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20T00:00:00.000+08:00","tokens":10}]}}"#)
        precondition(timestamp.days?.first?.day == "2026-10-20")
        var shanghai = utc
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let afterLocalMidnight = ISO8601DateFormatter().date(from: "2026-10-20T17:00:00Z")!
        let localWeek = payload.report(range: .week, now: afterLocalMidnight, calendar: shanghai)
        precondition(localWeek.days.last?.day == "2026-10-21")
        precondition(localWeek.days.first(where: { $0.day == "2026-10-20" })?.tokens == 200)
        var newYork = utc
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let dstNow = ISO8601DateFormatter().date(from: "2026-11-02T12:00:00Z")!
        let dstWeek = payload.report(range: .week, now: dstNow, calendar: newYork)
        precondition(dstWeek.days.count == 7 && Set(dstWeek.days.map(\.day)).count == 7)

        let huge = try parse(#"{"result":{"summary":{},"dailyUsageBuckets":[{"startDate":"2026-10-20","tokens":9223372036854775807},{"startDate":"2026-10-19","tokens":1}]}}"#)
        precondition(huge.days?.last?.tokens == Int64.max)
        precondition(huge.report(range: .week, now: now, calendar: utc).totalTokens == nil)
        let day = AccountUsageDay(day: "2024-02-29", tokens: 10)!
        let decodedDay = try JSONDecoder().decode(AccountUsageDay.self, from: JSONEncoder().encode(day))
        precondition(decodedDay == day)
        precondition(AccountUsageDay(day: "2026-02-29", tokens: 10) == nil)
        precondition(AccountUsageDay(day: "2026-10-20", tokens: -1) == nil)

        MeterLocalization.language = .simplifiedChinese
        precondition(AccountUsageRange.week.title == "7 天")
        precondition(AccountUsageSort.mostTokens.title == "用量从高到低")
        precondition(AccountUsageError.unsupported.errorDescription?.contains("更新 Codex") == true)
        print("Account analytics parsing, ranges, filters, missing data and date boundary checks passed")
    }
}
