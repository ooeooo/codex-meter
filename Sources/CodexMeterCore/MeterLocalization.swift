import Foundation

public enum MeterLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return MeterLocalization.text("Follow System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    public var locale: Locale {
        switch self {
        case .system: return MeterLocalization.resolve(.system).locale
        case .english: return Locale(identifier: "en_US")
        case .simplifiedChinese: return Locale(identifier: "zh_Hans_CN")
        }
    }
}

public enum MeterLocalization {
    // A single lock protects the app's preference when actor-isolated clients
    // produce errors or display models on background tasks.
    private final class LanguageStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var value: MeterLanguage = .system

        func read() -> MeterLanguage {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func write(_ language: MeterLanguage) {
            lock.lock()
            defer { lock.unlock() }
            value = language
        }
    }

    private static let storage = LanguageStorage()

    public static var language: MeterLanguage {
        get { storage.read() }
        set { storage.write(newValue) }
    }

    /// Resolve the first supported system language, falling back to English.
    /// The app offers Simplified Chinese for every Chinese locale.
    public static func resolve(
        _ language: MeterLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> MeterLanguage {
        guard language == .system else { return language }
        for identifier in preferredLanguages {
            let base = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first
            if base == "zh" { return .simplifiedChinese }
            if base == "en" { return .english }
        }
        return .english
    }

    public static var locale: Locale { resolve(language).locale }
    public static var isChinese: Bool { resolve(language) == .simplifiedChinese }

    public static func text(_ english: String) -> String {
        translated(english, language: resolve(language))
    }

    public static func format(_ englishFormat: String, _ arguments: CVarArg...) -> String {
        let resolved = resolve(language)
        return String(
            format: translated(englishFormat, language: resolved),
            locale: resolved.locale,
            arguments: arguments
        )
    }

    private static func translated(_ english: String, language: MeterLanguage) -> String {
        language == .simplifiedChinese ? (simplifiedChinese[english] ?? english) : english
    }

    private static let simplifiedChinese: [String: String] = [
        " Resets %@.": " 于 %@ 重置。",
        " Weekly pace: %@.": " 每周用量进度：%@。",
        "%@ %lld saved": "已节省 %@ %lld",
        "%@ tokens": "%@ 个 token",
        "%@. %d percent used; %d percent expected by now.": "%@。已用百分之 %d；当前预计应使用百分之 %d。",
        "%@: %d%% remaining. %@.%@%@": "%@：剩余 %d%%。%@。%@%@",
        "%@: %lld tokens": "%@：%lld 个 token",
        "%d %@, %d %@ until reset": "%d%@%d%@后重置",
        "%lld available for this account": "此账号可用次数：%lld",
        "%d percent remaining": "剩余百分之 %d",
        "%d percent remaining, %@%@": "剩余百分之 %d，%@%@",
        "%d percent remaining.": "剩余百分之 %d。",
        "%d%% remains in the tightest window": "最紧张的用量周期还剩 %d%%",
        "%d%% remains. %@": "剩余 %d%%。%@",
        "%d%% used · %d%% expected by now": "已用 %d%% · 当前预计应使用 %d%%",
        "%lld-hour limit": "%lld 小时限额",
        "%dd": "%d天",
        "%dd %dh": "%d天%d小时",
        "%dh": "%d小时",
        ", weekly pace %@": "，每周用量进度 %@",
        "5-hour limit": "5 小时限额",
        "API prices checked 15 Jul 2026 · estimate only": "API 价格核对于 2026 年 7 月 15 日 · 仅供估算",
        "API-equivalent ≈ %@": "等效 API 费用 ≈ %@",
        "Account ready": "账号已就绪",
        "Account removed": "账号已移除",
        "Active account": "当前账号",
        "Active profile: %@ (%@)": "当前账号：%@（%@）",
        "Activity chart": "活动图表",
        "Add Codex account": "添加 Codex 账号",
        "Add account…": "添加账号…",
        "Add…": "添加…",
        "Banked resets": "已累积重置次数",
        "CODEX_HOME: %@": "CODEX_HOME：%@",
        "Cached input": "缓存输入",
        "Cancel": "取消",
        "Checking %@…": "正在检查 %@…",
        "Checking Codex usage": "正在检查 Codex 用量",
        "Checking Codex usage…": "正在检查 Codex 用量…",
        "Choose a label. Codex Meter will open OpenAI's secure browser sign-in for a private profile on this Mac. Passwords and verification codes stay on OpenAI's page.": "输入账号名称。Codex Meter 将打开 OpenAI 的安全登录页面，并在此 Mac 上使用独立账号目录。密码和验证码仅在 OpenAI 页面输入。",
        "Choose whether to switch only Codex Meter, or also sign the Codex desktop app out and open OpenAI's secure browser login for this account.": "选择仅切换 Codex Meter，或同时退出 Codex 桌面应用，并通过 OpenAI 的安全浏览器登录此账号。",
        "Codex Meter diagnostics": "Codex Meter 诊断信息",
        "Codex account switch failed: %@": "Codex 账号切换失败：%@",
        "Codex account switched": "Codex 账号已切换",
        "Codex activity": "Codex 活动",
        "Codex could not be closed before signing out. Quit Codex and try again.": "退出登录前无法关闭 Codex。请先退出 Codex，再重试。",
        "Codex could not be opened: %@": "无法打开 Codex：%@",
        "Codex did not report a signed-in account after login.": "登录完成后，Codex 未返回已登录账号。",
        "Codex did not return usage data in time.": "Codex 未能及时返回用量数据。",
        "Codex is not installed in /Applications.": "未在 /Applications 中找到 Codex。",
        "Codex is not installed in a supported location.": "未在支持的位置找到 Codex，请先安装 Codex。",
        "Codex returned an unknown error.": "Codex 返回了未知错误。",
        "Codex returned an unsupported local usage record format.": "Codex 返回的本地用量记录格式不受支持。",
        "Codex returned usage data in an unknown format.": "Codex 返回的用量数据格式无法识别。",
        "Codex signed in as %@, not %@. Sign in again and choose the intended account.": "Codex 当前登录的是 %@，而非 %@。请重新登录并选择目标账号。",
        "Codex usage": "Codex 用量",
        "Codex usage is out of date. Last updated %@.": "Codex 用量已过期。上次更新于 %@。",
        "Codex usage is running low": "Codex 剩余用量不足",
        "Codex usage unavailable": "Codex 用量不可用",
        "Codex usage unavailable: %@": "Codex 用量不可用：%@",
        "Continue": "继续",
        "Copy Diagnostics": "复制诊断信息",
        "Could not start Codex: %@": "无法启动 Codex：%@",
        "Currency": "货币",
        "Current account: %@. Open account switcher": "当前账号：%@。打开账号切换菜单",
        "Daily limit": "每日限额",
        "Day": "日期",
        "Default": "默认",
        "Delete %@?": "删除 %@？",
        "Delete Account": "删除账号",
        "Delete account": "删除账号",
        "Delete…": "删除…",
        "Desktop switching uses OpenAI's secure sign-in.": "切换桌面账号使用 OpenAI 安全登录。",
        "Display, alerts and accounts": "显示、提醒和账号",
        "Estimated savings versus GPT-5.6 Sol": "与 GPT-5.6 Sol 相比的估算节省",
        "Estimated savings vs GPT-5.6 Sol: %@": "相较 GPT-5.6 Sol 的预计节省：%@",
        "Executable: %@": "可执行文件：%@",
        "Fallback USD price for unknown models": "未知模型的备用美元价格",
        "Follow System": "跟随系统",
        "Icon + percentage": "图标 + 百分比",
        "Icon only": "仅图标",
        "Input": "输入",
        "It resets %@.": "将于 %@ 重置。",
        "Language": "语言",
        "Last successful refresh: %@": "上次成功刷新：%@",
        "Last update is stale": "上次更新已过期",
        "Launch at login": "登录时启动",
        "Launch at login could not be changed: %@": "无法更改登录时启动设置：%@",
        "Less than 1 hour until reset": "距离重置不足 1 小时",
        "Local Codex session history could not be filtered.": "无法筛选本地 Codex 会话历史。",
        "Local Codex session history is not readable.": "无法读取本地 Codex 会话历史。",
        "Local activity": "本地活动",
        "Local activity unavailable": "本地活动不可用",
        "Local credentials were deleted": "本地登录凭据已删除",
        "Low-usage alert": "低配额提醒",
        "Menu bar": "菜单栏",
        "Menu bar display": "菜单栏显示",
        "Meter + Codex": "用量计 + Codex",
        "Meter Only": "仅用量计",
        "Nearly exhausted": "即将耗尽",
        "No Codex rate-limit windows were returned for this account.": "Codex 未返回此账号的用量限额。",
        "On pace": "进度正常",
        "Only used when a model has no bundled official price. USD per million tokens.": "仅用于尚未收录官方价格的模型，单位为美元 / 百万个 token。",
        "Open Codex": "打开 Codex",
        "Open Codex…": "打开 Codex…",
        "OpenAI did not return a banked reset count for this account": "OpenAI 未返回此账号的已累积重置次数",
        "OpenAI sign-in did not complete.": "OpenAI 登录未完成。",
        "OpenAI sign-in failed: %@": "OpenAI 登录失败：%@",
        "Output": "输出",
        "Percentage only": "仅百分比",
        "Process running: %@": "进程运行中：%@",
        "Protocol diagnostics: unavailable": "协议诊断信息不可用",
        "Protocol stage: %@": "协议阶段：%@",
        "Quit": "退出",
        "Quit Codex Meter": "退出 Codex Meter",
        "Refresh": "刷新",
        "Refresh Codex usage": "刷新 Codex 用量",
        "Refresh usage": "刷新用量",
        "Reset + percentage": "重置 + 百分比",
        "Reset banked": "已获得重置次数",
        "Reset credits currently available for this account": "此账号当前可用的重置次数",
        "Reset time unavailable": "重置时间不可用",
        "Resets %@": "%@重置",
        "Resetting now": "正在重置",
        "Running low": "配额不足",
        "Secure sign-in completed": "安全登录已完成",
        "Settings": "设置",
        "Seven days · read from local session logs": "最近七天 · 读取本地会话日志",
        "Seven-day Codex activity": "最近七天的 Codex 活动",
        "Seven-day local token activity": "最近七天的本地 token 用量",
        "Signed in through the Codex app": "通过 Codex 应用登录",
        "Signing Codex out…": "正在退出 Codex…",
        "Switch Codex account": "切换 Codex 账号",
        "Switch Meter": "切换用量计",
        "Switch to %@?": "切换到 %@？",
        "The Codex usage service stopped unexpectedly.": "Codex 用量服务意外停止。",
        "The OpenAI sign-in page could not be opened in your browser.": "无法在浏览器中打开 OpenAI 登录页面。",
        "The account profile could not be created: %@": "无法创建账号目录：%@",
        "The local account could not be deleted: %@": "无法删除本地账号：%@",
        "The local history filter could not be started.": "无法启动本地历史记录筛选器。",
        "The reset time is unavailable.": "重置时间不可用。",
        "This is the Codex desktop profile. Codex Meter will switch its usage view to the account currently signed in there.": "这是 Codex 桌面应用的账号。Codex Meter 将显示该应用当前登录账号的用量。",
        "This removes the locally saved Codex credentials and usage profile from this Mac. It does not delete the OpenAI account.": "这会删除此 Mac 上保存的 Codex 登录凭据和用量账号目录，不会删除 OpenAI 账号。",
        "Time: %@": "时间：%@",
        "Today %@": "今日 %@",
        "Token milestone": "Token 用量里程碑",
        "Tokens": "Token 数",
        "Try again": "重试",
        "Unpriced": "暂无价格",
        "Updated %@": "更新于 %@",
        "Usage data is unavailable.": "无法获取用量数据。",
        "Usage error: %@": "用量错误：%@",
        "Usage running low": "剩余用量不足",
        "Usage unavailable": "用量不可用",
        "Usage window": "用量周期",
        "Usage windows": "配额窗口",
        "Use account": "使用账号",
        "Version: %@": "版本：%@",
        "Waiting for secure OpenAI sign-in…": "正在等待 OpenAI 安全登录…",
        "Weekly limit": "每周限额",
        "Weekly pace": "每周用量进度",
        "Work": "工作",
        "You have used %lldM local tokens": "本地 Token 用量已达 %lld 百万",
        "app-server disconnected": "app-server 已断开连接",
        "day": "天",
        "days": "天",
        "default": "默认",
        "default CODEX_HOME": "默认 CODEX_HOME",
        "hour": "小时",
        "hours": "小时",
        "initialized": "已初始化",
        "isolated CODEX_HOME": "独立 CODEX_HOME",
        "isolated profile": "独立账号目录",
        "no": "否",
        "none": "无",
        "not resolved": "未找到",
        "not started": "尚未启动",
        "rate limits received": "已收到限额数据",
        "remaining": "剩余",
        "starting app-server": "正在启动 app-server",
        "tokens": "token",
        "usage is %@ ahead": "用量超前 %@",
        "usage is %@ under pace": "用量落后 %@",
        "waiting for account/rateLimits/read": "正在等待 account/rateLimits/read",
        "waiting for initialize response": "正在等待初始化响应",
        "yes": "是"
    ]
}
