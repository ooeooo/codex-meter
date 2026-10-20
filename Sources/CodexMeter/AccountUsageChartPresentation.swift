import CodexMeterCore
import Foundation

enum AccountUsageChartPresentation {
    private static let numberLocale = Locale(identifier: "en_US")

    static func millions(_ tokens: Int64) -> Double { Double(tokens) / 1_000_000 }

    static func millionLabel(_ value: Double) -> String {
        // Promote values that would round to 1,000M to the billion unit.
        let useBillions = abs(value) >= 999.995
        let scaled = useBillions ? value / 1_000 : value
        let decimals = scaled != 0 && abs(scaled) < 0.01 ? 9 : 2
        let number = scaled.formatted(.number.locale(numberLocale)
            .precision(.fractionLength(0...decimals)).grouping(.automatic))
        return number + (useBillions ? "B" : "M")
    }

    static func groupedCount(_ value: Int64) -> String {
        value.formatted(.number.locale(numberLocale).grouping(.automatic))
    }

    static func compactCount(_ value: Int64) -> String {
        value >= 1_000_000 ? millionLabel(millions(value)) : groupedCount(value)
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
