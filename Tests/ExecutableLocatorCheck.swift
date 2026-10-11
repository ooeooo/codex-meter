import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
struct ExecutableLocatorCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)

        let current = root.appendingPathComponent("Renamed Current Desktop.app", isDirectory: true)
        let currentExecutable = try makeBundle(current, identifier: "com.openai.codex")
        let stale = root.appendingPathComponent("Codex.app", isDirectory: true)
        let staleExecutable = try makeBundle(stale, identifier: "com.openai.codex")
        let classic = root.appendingPathComponent("ChatGPT Classic.app", isDirectory: true)
        let classicExecutable = try makeBundle(classic, identifier: "com.openai.chat")
        let invalid = root.appendingPathComponent("Invalid.app", isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)

        let desktopCandidates = CodexExecutableLocator.candidatePaths(
            home: home.path, environment: [:], appBundleURLs: [classic, invalid, current, current, stale]
        )
        precondition(desktopCandidates.prefix(2).elementsEqual([currentExecutable.path, staleExecutable.path]))
        precondition(!desktopCandidates.contains(classicExecutable.path))
        precondition(!desktopCandidates.contains(invalid.appendingPathComponent("Contents/Resources/codex").path))
        precondition(Set(desktopCandidates).count == desktopCandidates.count)
        precondition(CodexExecutableLocator.locate(
            home: home.path, environment: [:], appBundleURLs: [current, stale]
        ) == currentExecutable)

        let override = root.appendingPathComponent("custom/codex")
        try makeExecutable(override)
        precondition(CodexExecutableLocator.locate(
            home: home.path, environment: ["CODEX_PATH": override.path], appBundleURLs: [current]
        ) == override)
        for invalidOverride in ["relative/codex", root.appendingPathComponent("missing").path, root.path] {
            precondition(CodexExecutableLocator.locate(
                home: home.path, environment: ["CODEX_PATH": invalidOverride], appBundleURLs: [current]
            ) == currentExecutable)
        }

        let pathDirectory = root.appendingPathComponent("nvm/node/bin", isDirectory: true)
        let pathExecutable = pathDirectory.appendingPathComponent("codex")
        try makeExecutable(pathExecutable)
        let pathCandidates = CodexExecutableLocator.candidatePaths(
            home: home.path,
            environment: ["PATH": ":.:relative/bin:\(pathDirectory.path):\(pathDirectory.path)/.:/opt/homebrew/bin"]
        )
        let pathIndex = pathCandidates.firstIndex(of: pathExecutable.path)!
        precondition(pathIndex < pathCandidates.firstIndex(of: "/opt/homebrew/bin/codex")!)
        precondition(pathCandidates.filter { $0 == pathExecutable.path }.count == 1)
        precondition(pathCandidates.allSatisfy { $0.hasPrefix("/") })
        precondition(!pathCandidates.contains { $0.hasSuffix("relative/bin/codex") })

        let userCurrent = home.appendingPathComponent("Applications/ChatGPT.app", isDirectory: true)
        let userCurrentExecutable = try makeBundle(userCurrent, identifier: "com.openai.codex")
        let userStale = home.appendingPathComponent("Applications/Codex.app", isDirectory: true)
        let userStaleExecutable = try makeBundle(userStale, identifier: "com.openai.codex")
        let userCandidates = CodexExecutableLocator.candidatePaths(home: home.path, environment: [:])
        precondition(userCandidates.firstIndex(of: userCurrentExecutable.path)! < userCandidates.firstIndex(of: userStaleExecutable.path)!)

        // A readable plist alone is not enough: the selected process must be executable.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: currentExecutable.path)
        precondition(CodexExecutableLocator.locate(
            home: home.path, environment: [:], appBundleURLs: [current, stale]
        ) == staleExecutable)
        print("Executable discovery checks passed")
    }

    private static func makeBundle(_ app: URL, identifier: String) throws -> URL {
        let executable = app.appendingPathComponent("Contents/Resources/codex")
        try makeExecutable(executable)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0
        )
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return executable
    }

    private static func makeExecutable(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
