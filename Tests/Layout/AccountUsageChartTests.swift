import CodexMeterCore
import Foundation
import XCTest
@testable import CodexMeter

final class AccountUsageChartTests: XCTestCase {
    func testMillionsStayReadableWithoutScientificNotation() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(AccountUsageChartPresentation.millionLabel(1.25, locale: locale, chinese: true), "1.25兆")
        XCTAssertEqual(AccountUsageChartPresentation.millionLabel(1.25, locale: locale, chinese: false), "1.25M")
        XCTAssertEqual(AccountUsageChartPresentation.millionLabel(0.000001, locale: locale, chinese: true), "0.000001兆")
        for tokens: Int64 in [0, 1, 500, 1_000_000, 1_250_000, Int64.max] {
            let label = AccountUsageChartPresentation.millionLabel(AccountUsageChartPresentation.millions(tokens), locale: locale, chinese: false)
            XCTAssertFalse(label.lowercased().contains("e"))
            XCTAssertTrue(label.hasSuffix("M"))
        }
    }

    func testAxisDatesUseFourCompleteLabelsAcrossBothRanges() {
        let now = AccountUsageDay.date(for: "2026-10-20")!
        let payload = AccountUsagePayload(summary: AccountUsageSummary(), days: [], fetchedAt: now)
        for range in AccountUsageRange.allCases {
            let report = payload.report(range: range, now: now, calendar: AccountUsageDay.calendar)
            let dates = AccountUsageChartPresentation.axisDates(report.days)
            let labels = dates.map(AccountUsageChartPresentation.dateLabel)
            XCTAssertEqual(dates.count, 4)
            XCTAssertEqual(Set(labels).count, 4)
            XCTAssertEqual(labels.first, range == .week ? "10/14" : "09/21")
            XCTAssertEqual(labels.last, "10/20")
            XCTAssertTrue(labels.allSatisfy { $0.count == 5 && !$0.contains("…") })
        }
    }

    func testPointerDatePreservesSourceDayAndMissingUsage() {
        let days = [AccountUsageDay(day: "2026-10-19", tokens: nil)!, AccountUsageDay(day: "2026-10-20", tokens: 0)!]
        XCTAssertEqual(AccountUsageChartPresentation.day(at: days[0].date.addingTimeInterval(86_399), in: days), "2026-10-19")
        XCTAssertEqual(AccountUsageChartPresentation.day(at: days[1].date, in: days), "2026-10-20")
        XCTAssertNil(AccountUsageChartPresentation.day(at: days[0].date.addingTimeInterval(-1), in: days))
        XCTAssertNil(days[0].tokens)
        XCTAssertEqual(days[1].tokens, 0)
    }
}
