import Foundation

/// Finds the existing official Codex process without invoking a shell or reading login data.
public enum CodexExecutableLocator {
    private static let desktopBundleIdentifier = "com.openai.codex"

    public static func candidatePaths(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appBundleURLs: [URL] = []
    ) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func append(_ path: String) {
            guard path.hasPrefix("/") else { return }
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            if seen.insert(normalized).inserted { candidates.append(normalized) }
        }

        func appendDesktopBundle(_ appURL: URL) {
            for path in desktopCandidatePaths(in: appURL) { append(path) }
        }

        if let override = environment["CODEX_PATH"], override.hasPrefix("/"), isExecutableFile(override) {
            append(override)
        }

        // Callers can supply running and Launch Services bundles, including renamed apps.
        for appURL in appBundleURLs { appendDesktopBundle(appURL) }

        // The current unified desktop is named ChatGPT; prefer it over a stale Codex app.
        for appName in ["ChatGPT.app", "Codex.app"] {
            for applicationsDirectory in ["/Applications", "\(home)/Applications"] {
                appendDesktopBundle(URL(fileURLWithPath: applicationsDirectory)
                    .appendingPathComponent(appName, isDirectory: true))
            }
        }

        // Relative PATH entries depend on the launch directory and are deliberately ignored.
        for directory in (environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: true) {
            guard directory.hasPrefix("/") else { continue }
            append(URL(fileURLWithPath: String(directory)).appendingPathComponent("codex").path)
        }

        for path in [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.volta/bin/codex"
        ] {
            append(path)
        }
        return candidates
    }

    public static func locate(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        appBundleURLs: [URL] = []
    ) -> URL? {
        candidatePaths(home: home, environment: environment, appBundleURLs: appBundleURLs)
            .first(where: isExecutableFile)
            .map { URL(fileURLWithPath: $0) }
    }

    /// Resolves the CLI bundled with the desktop app, never its Electron GUI executable.
    public static func desktopExecutableURL(in appURL: URL) -> URL? {
        desktopCandidatePaths(in: appURL)
            .first(where: isExecutableFile)
            .map { URL(fileURLWithPath: $0) }
    }

    private static func desktopCandidatePaths(in appURL: URL) -> [String] {
        guard appURL.isFileURL,
              let data = try? Data(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = plist["CFBundleIdentifier"] as? String,
              identifier.caseInsensitiveCompare(desktopBundleIdentifier) == .orderedSame else { return [] }

        // September 2026 desktop builds moved the service into codex-cli.
        // Prefer its declared launcher; retain the signed native binary and legacy layout.
        return [
            "Contents/Resources/codex-cli/bin/codex",
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex"
        ].map { appURL.appendingPathComponent($0).standardizedFileURL.path }
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }
}
