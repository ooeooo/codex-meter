import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
struct AccountQuotaHistoryCheck {
    static let start = Date(timeIntervalSince1970: 2_000_000_000)

    static func snapshot(_ seconds: Double, used: Int = 20, weeklyUsed: Int? = 30,
                         reset: Double? = 18_000, weeklyReset: Double = 604_800,
                         plan: String = "plus", duration: Int = 300,
                         balance: String? = "100", resetCredits: Int? = 3) -> RateLimitPayload {
        RateLimitPayload(
            snapshot: RateLimitSnapshot(limitID: "codex", limitName: "Codex", planType: plan,
                primary: RateLimitWindow(usedPercent: used, resetsAt: reset.map { start.addingTimeInterval($0) }, durationMinutes: duration),
                secondary: weeklyUsed.map { RateLimitWindow(usedPercent: $0, resetsAt: start.addingTimeInterval(weeklyReset), durationMinutes: 10_080) },
                credits: balance.map { AccountCredits(hasCredits: true, unlimited: false, balance: $0) }),
            fetchedAt: start.addingTimeInterval(seconds), availableResetCredits: resetCredits, accountID: "account-a")
    }

    static func main() async throws {
        MeterLocalization.language = .english
        var history = AccountQuotaHistory(accountKey: "account-a")
        history.record(snapshot(0))
        precondition(history.observations[0].changes.allSatisfy { $0.kind == .baseline && $0.decreasePoints == nil })
        precondition(history.recentChanges.isEmpty)

        // A restart within a cycle recovers the net account decrease, including
        // other devices. Neither window is added to the other or assigned a day.
        history.record(snapshot(3_600, used: 45, weeklyUsed: 40))
        let gap = history.observations.last!
        precondition(gap.hasGap && gap.previousFetchedAt == start)
        precondition(gap.changes.map(\.decreasePoints) == [25, 10])
        precondition(history.chartPoints[0].segment != history.chartPoints[1].segment)
        history.record(snapshot(3_720, used: 50, weeklyUsed: 40))
        precondition(history.observations.last?.hasGap == false)
        precondition(history.observations.last?.changes.first?.decreasePoints == 5)
        precondition(history.chartPoints[1].segment == history.chartPoints[2].segment)

        // A changed reset deadline detects a new cycle even when current usage
        // exceeds the old value. No subtraction can recover interval usage.
        history.record(snapshot(20_000, used: 80, weeklyUsed: 40, reset: 38_000))
        precondition(history.observations.last?.changes.first?.kind == .cycleChanged)
        precondition(history.observations.last?.changes.first?.decreasePoints == nil)
        precondition(history.observations.last?.changes.first?.currentCycleUsedPercent == 80)
        precondition(history.observations.last?.changes.first?.previousResetAt == start.addingTimeInterval(18_000))
        precondition(history.observations.last?.changes.first?.resetsAt == start.addingTimeInterval(38_000))
        precondition(history.observations.last?.changes.first?.resetDetail != nil)
        precondition(history.observations.last?.changes.last?.kind == .unchanged)
        precondition(history.chartPoints[2].segment != history.chartPoints[3].segment)

        // Hitting the advertised reset time with a stale server response must
        // break the cycle even if the quota percentage has not changed at all.
        var pending = AccountQuotaHistory(accountKey: "account-a")
        pending.record(snapshot(17_880, used: 80))
        pending.record(snapshot(18_000, used: 80))
        precondition(pending.observations.last?.changes.first?.kind == .resetPending)
        precondition(pending.observations.last?.hasChanges == true)
        precondition(pending.observations.last?.changes.first?.decreasePoints == nil)
        precondition(pending.observations.last?.changes.first?.currentCycleUsedPercent == nil)
        precondition(pending.chartPoints[0].segment != pending.chartPoints[1].segment)
        pending.record(snapshot(18_120, used: 80))
        precondition(pending.observations.last?.changes.first?.kind == .resetPending)
        precondition(pending.observations.last?.hasChanges == false)
        precondition(pending.recentChanges.count == 1)
        pending.record(snapshot(18_240, used: 85))
        precondition(pending.observations.last?.changes.first?.kind == .resetPending)
        precondition(pending.observations.last?.changes.first?.decreasePoints == nil)
        pending.record(snapshot(18_360, used: 5, reset: 36_000))
        precondition(pending.observations.last?.changes.first?.kind == .cycleChanged)
        precondition(pending.observations.last?.changes.first?.currentCycleUsedPercent == 5)
        precondition(pending.observations.last?.changes.first?.decreasePoints == nil)
        pending.record(snapshot(18_480, used: 8, reset: 36_000))
        precondition(pending.observations.last?.changes.first?.decreasePoints == 3)

        // A deadline that advances but is still in the past is not a fresh cycle.
        var staleDeadline = AccountQuotaHistory(accountKey: "account-a")
        staleDeadline.record(snapshot(0))
        staleDeadline.record(snapshot(80_000, used: 10, reset: 36_000))
        precondition(staleDeadline.observations.last?.changes.first?.kind == .resetPending)
        precondition(staleDeadline.observations.last?.changes.first?.currentCycleUsedPercent == nil)

        var replenished = AccountQuotaHistory(accountKey: "account-a")
        replenished.record(snapshot(0, used: 90))
        replenished.record(snapshot(120, used: 5))
        precondition(replenished.observations.last?.changes.first?.kind == .replenished)
        precondition(replenished.observations.last?.changes.first?.decreasePoints == nil)
        // An early reset may also move the deadline without crossing its old end.
        replenished.record(snapshot(240, used: 10, reset: 25_000))
        precondition(replenished.observations.last?.changes.first?.kind == .definitionChanged)

        var changed = AccountQuotaHistory(accountKey: "account-a")
        changed.record(snapshot(0))
        changed.record(snapshot(120, used: 80, plan: "pro"))
        precondition(changed.observations.last?.changes.allSatisfy { $0.kind == .definitionChanged } == true)
        changed.record(snapshot(240, used: 90, weeklyUsed: nil, plan: "pro", duration: 360))
        precondition(changed.observations.last?.changes.first?.kind == .definitionChanged)
        precondition(changed.observations.last?.changes.last?.kind == .unavailable)

        var missing = AccountQuotaHistory(accountKey: "account-a")
        missing.record(snapshot(0, reset: nil))
        missing.record(snapshot(120, used: 50, reset: nil, balance: nil, resetCredits: nil))
        precondition(missing.observations.last?.changes.first?.decreasePoints == nil)
        precondition(missing.observations.last?.payload.snapshot.credits == nil)
        precondition(missing.observations.last?.payload.availableResetCredits == nil)
        // A past reset time with no fresh deadline must not be treated as the
        // same cycle, even when the backend continues returning an old window.
        missing.record(snapshot(30_000, used: 80))
        precondition(missing.observations.last?.changes.first?.kind == .resetPending)

        var credits = AccountQuotaHistory(accountKey: "account-a")
        credits.record(snapshot(0))
        credits.record(snapshot(120, balance: "90.5", resetCredits: 2))
        precondition(credits.observations.last?.balanceChanged == true)
        precondition(credits.observations.last?.resetCreditsChanged == true)
        precondition(credits.observations.last?.changes.allSatisfy { $0.kind == .unchanged } == true)
        precondition(credits.recentChanges.count == 1) // A count decrease alone proves no reset.
        credits.record(snapshot(120, used: 100))
        credits.record(snapshot(60, used: 100))
        precondition(credits.observations.count == 2)

        var longGap = AccountQuotaHistory(accountKey: "account-a")
        longGap.record(snapshot(0))
        longGap.record(snapshot(21 * 86_400, used: 95, reset: 21 * 86_400 + 18_000, weeklyReset: 28 * 86_400))
        precondition(longGap.observations.count == 1)
        precondition(longGap.observations[0].previousFetchedAt == start)
        precondition(longGap.observations[0].changes.allSatisfy { $0.kind == .cycleChanged && $0.decreasePoints == nil })

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let days = history.dailyRemainingPercent(now: start.addingTimeInterval(20_000), calendar: utc)
        precondition(days.count == 7 && days.suffix(1).first! == 60)
        precondition(days.dropLast().allSatisfy { $0 == nil })
        let roundTripped = try JSONDecoder().decode(AccountQuotaHistory.self, from: JSONEncoder().encode(history))
        precondition(roundTripped == history)
        let legacyChange = #"{"window":"primary","kind":"cycleChanged","previousRemaining":10,"remaining":80,"durationMinutes":300}"#
        let decodedChange = try JSONDecoder().decode(AccountQuotaChange.self, from: Data(legacyChange.utf8))
        precondition(decodedChange.previousResetAt == nil && decodedChange.resetsAt == nil)
        precondition(decodedChange.currentCycleUsedPercent == 20)
        precondition(decodedChange.resetDetail == nil)

        // Verify real disk reload, profile and identity isolation, and an
        // offline interval spanning several resets after restarting the store.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = UUID(), otherProfile = UUID()
        let store = AccountQuotaHistoryStore(directory: directory)
        _ = try await store.record(snapshot(0), profileID: profile, accountKey: "a")
        let otherAccount = try await store.record(snapshot(120, used: 99), profileID: profile, accountKey: "b")
        precondition(otherAccount.observations.count == 1 && otherAccount.recentChanges.isEmpty)
        let isolated = try await store.record(snapshot(120), profileID: otherProfile, accountKey: "a")
        precondition(isolated.observations.count == 1)
        let reloaded = AccountQuotaHistoryStore(directory: directory)
        let resumed = try await reloaded.record(snapshot(3_600, used: 60), profileID: profile, accountKey: "a")
        precondition(resumed.observations.count == 2)
        precondition(resumed.observations.last?.changes.first?.decreasePoints == 40)
        let crossed = try await AccountQuotaHistoryStore(directory: directory).record(
            snapshot(21 * 86_400, reset: 21 * 86_400 + 18_000, weeklyReset: 28 * 86_400), profileID: profile, accountKey: "a")
        precondition(crossed.observations[0].changes.first?.kind == .cycleChanged)
        precondition(crossed.observations[0].previousFetchedAt == start.addingTimeInterval(3_600))

        // Corruption must be surfaced without overwriting the existing archive.
        let badProfile = UUID()
        let badURL = directory.appendingPathComponent(badProfile.uuidString + ".json")
        let badData = Data("corrupt".utf8)
        try badData.write(to: badURL)
        do {
            _ = try await AccountQuotaHistoryStore(directory: directory).record(snapshot(0), profileID: badProfile, accountKey: "a")
            preconditionFailure("Corrupt archive should not be replaced")
        } catch {
            let preserved = try Data(contentsOf: badURL)
            precondition(preserved == badData)
        }
        let blockedDirectory = directory.appendingPathComponent("file-not-directory")
        try badData.write(to: blockedDirectory)
        do {
            _ = try await AccountQuotaHistoryStore(directory: blockedDirectory).record(snapshot(0), profileID: profile, accountKey: "a")
            preconditionFailure("Disk failure should not be hidden")
        } catch {}
        try await store.remove(profileID: profile)
        try await store.remove(profileID: profile)
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(profile.uuidString + ".json").path))

        MeterLocalization.language = .simplifiedChinese
        precondition(gap.changes[0].summary == "5 小时限额：余量净减少 25 个百分点（80% → 55%）")
        precondition(history.observations.last!.changes[0].summary.contains("新配额周期"))
        precondition(history.observations.last!.changes[0].summary.contains("已用 80%"))
        precondition(staleDeadline.observations.last!.changes[0].summary.contains("等待配额更新"))
        precondition(AccountCredits(hasCredits: true, unlimited: true, balance: nil).displayBalance == "无限额")
        print("Account quota history checks passed")
    }
}
