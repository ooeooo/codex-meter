import CodexMeterCore
import Foundation

enum AccountUsageChartPresentation {
    static func millions(_ tokens: Int64) -> Double { Double(tokens) / 1_000_000 }

    static func millionLabel(_ value: Double, locale: Locale = MeterLocalization.locale, chinese: Bool = MeterLocalization.isChinese) -> String {
        let number = value.formatted(.number.locale(locale).precision(.fractionLength(0...9)).grouping(.never))
        return number + (chinese ? "兆" : "M")
    }

    static func axisDates(_ days: [AccountUsageDay]) -> [Date] {
        guard !days.isEmpty else { return [] }
        let count = min(4, days.count)
        return (0..<count).map { index in
            let offset = count == 1 ? 0 : index * (days.count - 1) / (count - 1)
            return days[offset].date.addingTimeInterval(43_200)
        }
    }

    static func dateLabel(_ date: Date) -> String {
        String(AccountUsageDay.key(for: date, calendar: AccountUsageDay.calendar).suffix(5))
            .replacingOccurrences(of: "-", with: "/")
    }

    static func day(at date: Date, in days: [AccountUsageDay]) -> String? {
        let key = AccountUsageDay.key(for: date, calendar: AccountUsageDay.calendar)
        return days.first(where: { $0.day == key })?.day
    }
}
