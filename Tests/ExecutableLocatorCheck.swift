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
        precondition(desktopCandidates.firstIndex(of: currentExecutable.path)! < desktopCandidates.firstIndex(of: staleExecutable.path)!)
        precondition(!desktopCandidates.contains(classicExecutable.path))
        precondition(!desktopCandidates.contains(invalid.appendingPathComponent("Contents/Resources/codex").path))
        precondition(Set(desktopCandidates).count == desktopCandidates.count)
        precondition(CodexExecutableLocator.locate(
            home: home.path, environment: [:], appBundleURLs: [current, stale]
        ) == currentExecutable)
        precondition(CodexExecutableLocator.desktopExecutableURL(in: current) == currentExecutable)
        precondition(CodexExecutableLocator.desktopExecutableURL(in: classic) == nil)
        precondition(CodexExecutableLocator.desktopExecutableURL(in: invalid) == nil)
        try checkPackagedDesktopLayouts(root: root)

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
        print("Executable discovery and legacy/packaged desktop layout checks passed")
    }

    private static func checkPackagedDesktopLayouts(root: URL) throws {
        let launcherPath = "Contents/Resources/codex-cli/bin/codex"
        let nestedPath = "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        for appName in ["Codex.app", "ChatGPT.app"] {
            for path in [launcherPath, nestedPath] {
                let kind = path == launcherPath ? "launcher-only" : "nested-only"
                let app = root.appendingPathComponent("\(kind)/\(appName)", isDirectory: true)
                let executable = try makeBundle(app, identifier: "com.openai.codex", executablePath: path)
                precondition(CodexExecutableLocator.desktopExecutableURL(in: app) == executable)
                precondition(CodexExecutableLocator.locate(
                    home: root.path, environment: [:], appBundleURLs: [app]
                ) == executable)
            }
        }

        let combined = root.appendingPathComponent("Both Layouts With Spaces/Codex.app", isDirectory: true)
        let nested = try makeBundle(combined, identifier: "COM.OpenAI.CoDeX", executablePath: nestedPath)
        let launcher = combined.appendingPathComponent(launcherPath)
        try makeExecutable(launcher)
        let legacy = combined.appendingPathComponent("Contents/Resources/codex")
        try makeExecutable(legacy)
        precondition(CodexExecutableLocator.desktopExecutableURL(in: combined) == launcher)
        let candidates = CodexExecutableLocator.candidatePaths(
            home: root.path, environment: [:], appBundleURLs: [combined]
        )
        precondition(candidates.firstIndex(of: launcher.path)! < candidates.firstIndex(of: nested.path)!)
        precondition(candidates.firstIndex(of: nested.path)! < candidates.firstIndex(of: legacy.path)!)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: launcher.path)
        precondition(CodexExecutableLocator.desktopExecutableURL(in: combined) == nested)
        try FileManager.default.removeItem(at: launcher)
        try FileManager.default.createSymbolicLink(
            at: launcher, withDestinationURL: root.appendingPathComponent("missing-wrapper-target")
        )
        precondition(CodexExecutableLocator.desktopExecutableURL(in: combined) == nested)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nested.path)
        precondition(CodexExecutableLocator.desktopExecutableURL(in: combined) == legacy)

        let guiOnly = root.appendingPathComponent("GUI Only/Codex.app", isDirectory: true)
        _ = try makeBundle(guiOnly, identifier: "com.openai.codex", executablePath: "Contents/MacOS/Codex")
        precondition(CodexExecutableLocator.desktopExecutableURL(in: guiOnly) == nil)
        let classic = root.appendingPathComponent("Classic Modern Layout/ChatGPT.app", isDirectory: true)
        let classicExecutable = try makeBundle(classic, identifier: "com.openai.chat", executablePath: launcherPath)
        precondition(CodexExecutableLocator.desktopExecutableURL(in: classic) == nil)
        precondition(!CodexExecutableLocator.candidatePaths(
            home: root.path, environment: [:], appBundleURLs: [classic]
        ).contains(classicExecutable.path))
    }

    private static func makeBundle(
        _ app: URL, identifier: String, executablePath: String = "Contents/Resources/codex"
    ) throws -> URL {
        let executable = app.appendingPathComponent(executablePath)
        try makeExecutable(executable)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Codex"], format: .xml, options: 0
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
