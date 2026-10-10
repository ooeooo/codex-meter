import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
enum LocalizationCheck {
    static func main() throws {
        let original = MeterLocalization.language
        defer { MeterLocalization.language = original }

        precondition(MeterLanguage(rawValue: "zh-Hans") == .simplifiedChinese)
        precondition(MeterLanguage.allCases.map(\.id) == ["system", "en", "zh-Hans"])
        precondition(MeterLocalization.resolve(.system, preferredLanguages: ["zh-Hans-CN", "en-US"]) == .simplifiedChinese)
        precondition(MeterLocalization.resolve(.system, preferredLanguages: ["zh_CN"]) == .simplifiedChinese)
        precondition(MeterLocalization.resolve(.system, preferredLanguages: ["zh-Hant-TW"]) == .simplifiedChinese)
        precondition(MeterLocalization.resolve(.system, preferredLanguages: ["fr-FR", "zh"]) == .simplifiedChinese)
        precondition(MeterLocalization.resolve(.system, preferredLanguages: ["en-GB", "zh-Hans"]) == .english)
        precondition(MeterLocalization.resolve(.system, preferredLanguages: ["fr-FR"]) == .english)
        precondition(MeterLocalization.resolve(.system, preferredLanguages: []) == .english)
        precondition(MeterLocalization.resolve(.english, preferredLanguages: ["zh-Hans"]) == .english)

        MeterLocalization.language = .english
        let window = RateLimitWindow(usedPercent: 25, resetsAt: nil, durationMinutes: 480)
        precondition(window.displayName == "8-hour limit")
        precondition(MeterLanguage.system.displayName == "Follow System")
        precondition(CodexClientError.launch("permission denied").errorDescription == "Could not start Codex: permission denied")
        precondition(MeterLocalization.format("Remaining: %d%%", 75) == "Remaining: 75%")
        let profileName = "研发 100% / %@ %n"
        precondition(MeterLocalization.format("Delete %@?", profileName) == "Delete 研发 100% / %@ %n?")
        precondition(MeterLocalization.format("%d%% remains. %@", 0, "It resets tomorrow.") == "0% remains. It resets tomorrow.")
        let encodedEnglish = try JSONEncoder().encode(window)

        MeterLocalization.language = .simplifiedChinese
        precondition(MeterLocalization.isChinese)
        precondition(MeterLocalization.locale.identifier == "zh_Hans_CN")
        precondition(MeterLanguage.system.displayName == "跟随系统")
        precondition(MeterLanguage.english.displayName == "English")
        precondition(MeterLanguage.simplifiedChinese.displayName == "简体中文")
        precondition(window.displayName == "8 小时限额")
        precondition(MeterLocalization.text("Uncatalogued server detail") == "Uncatalogued server detail")
        precondition(MeterLocalization.format("Could not start Codex: %@", "/Applications/A%20.app") == "无法启动 Codex：/Applications/A%20.app")
        precondition(CodexClientError.timedOut.errorDescription == "Codex 未能及时返回用量数据。")
        precondition(CodexClientError.server("Codex returned an unknown error.").errorDescription == "Codex 返回了未知错误。")
        precondition(CodexClientError.server("Error: user 123").errorDescription == "Error: user 123")
        precondition(LocalActivityError.unreadableSource.errorDescription == "无法读取本地 Codex 会话历史。")

        // A translated template must preserve each dynamic value, escape the
        // literal percent sign, and never parse user labels as format strings.
        precondition(MeterLocalization.format("Delete %@?", profileName) == "删除 研发 100% / %@ %n？")
        precondition(MeterLocalization.format("Active profile: %@ (%@)", profileName, MeterLocalization.text("isolated CODEX_HOME")) == "当前账号：研发 100% / %@ %n（独立 CODEX_HOME）")
        precondition(MeterLocalization.format("%d%% remains. %@", 0, "将于明日重置。") == "剩余 0%。将于明日重置。")
        precondition(MeterLocalization.format("%d%% used · %d%% expected by now", 100, 50) == "已用 100% · 当前预计应使用 50%")
        precondition(MeterLocalization.format("%@: %d%% remaining. %@.%@%@", "每周限额", 75, "2天8小时后重置", "", "") == "每周限额：剩余 75%。2天8小时后重置。")
        precondition(MeterLocalization.format("OpenAI sign-in failed: %@", "bad 100% %@ %n") == "OpenAI 登录失败：bad 100% %@ %n")
        precondition(MeterLocalization.format("%@: %lld tokens", "周六", Int64.max) == "周六：9,223,372,036,854,775,807 个 token")

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let countdown = ResetCountdownFormatter.format(until: now.addingTimeInterval(2 * 86_400 + 8 * 3_600), now: now)
        precondition(countdown.daysText == "2d")
        precondition(countdown.hoursText == "8h")
        precondition(countdown.accessibilityText == "2天8小时后重置")
        precondition(ResetCountdownFormatter.format(until: now.addingTimeInterval(300), now: now).accessibilityText == "距离重置不足 1 小时")
        precondition(ResetCountdownFormatter.format(until: nil, now: now).accessibilityText == "重置时间不可用")
        let weekly = RateLimitWindow(usedPercent: 75, resetsAt: now.addingTimeInterval(3.5 * 86_400), durationMinutes: 10_080)
        precondition(weekly.displayName == "每周限额")
        precondition(WeeklyPace(window: weekly, now: now)?.summaryText == "用量超前 1天18小时")

        // Language selection changes display strings, never raw model data or
        // the JSON schema used by the CLI and exported snapshots.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let chineseJSON = try encoder.encode(window)
        let parsedEnglish = try JSONSerialization.jsonObject(with: encodedEnglish) as! NSDictionary
        let parsedChinese = try JSONSerialization.jsonObject(with: chineseJSON) as! NSDictionary
        precondition(parsedEnglish == parsedChinese)
        MeterLocalization.language = .english
        precondition(window.displayName == "8-hour limit")
        precondition(!MeterLocalization.isChinese)
        print("Localization checks passed")
    }
}
