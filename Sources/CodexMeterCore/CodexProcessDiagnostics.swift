import Foundation

/// Bounded, sanitized diagnostics from the local Codex process. The reader and
/// client actor can access this buffer concurrently without exposing raw output.
public final class CodexProcessDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var tail = Data()
    private var startsAtLineBoundary = true
    private static let maximumBytes = 8_192

    public init() {}

    public func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if data.count >= Self.maximumBytes {
            let keepStart = data.index(data.endIndex, offsetBy: -Self.maximumBytes)
            startsAtLineBoundary = keepStart == data.startIndex
                ? (tail.isEmpty ? startsAtLineBoundary : tail.last == 0x0A)
                : data[data.index(before: keepStart)] == 0x0A
            tail = Data(data.suffix(from: keepStart))
            return
        }
        let removedCount = max(0, tail.count + data.count - Self.maximumBytes)
        if removedCount > 0 {
            let lastRemoved = tail.index(tail.startIndex, offsetBy: removedCount - 1)
            startsAtLineBoundary = tail[lastRemoved] == 0x0A
            tail.removeFirst(removedCount)
        }
        tail.append(data)
    }

    public func summary() -> String {
        lock.lock()
        var snapshot = tail
        let hasPartialFirstLine = !startsAtLineBoundary
        lock.unlock()

        // A clipped line may have lost the label identifying a credential.
        // Discard it entirely, including when the process hasn't ended it yet.
        if hasPartialFirstLine {
            guard let newline = snapshot.firstIndex(of: 0x0A) else { return "" }
            snapshot = Data(snapshot.suffix(from: snapshot.index(after: newline)))
        }

        return Self.redact(String(decoding: snapshot, as: UTF8.self))
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(8)
            .map { line in
                line.count > 400 ? String(line.prefix(399)) + "…" : line
            }
            .joined(separator: "\n")
    }

    /// Sanitize copied diagnostics too, including server errors received over
    /// JSON-RPC rather than stderr. User labels are never treated as formats.
    public static func redact(_ text: String) -> String {
        var cleaned = replacing(
            #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|\x1B\[[0-?]*[ -/]*[@-~]|\x1B[@-_]"#,
            in: text,
            with: ""
        )
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        cleaned = replacing(#"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]"#, in: cleaned, with: "")

        return cleaned.components(separatedBy: "\n").map { line in
            if line.range(
                of: #"authorization|bearer|password|token|api[\s_-]*key|secret|auth\.json"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                return "[REDACTED]"
            }
            var safe = replacing(#"\beyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, in: line, with: "[REDACTED]")
            safe = replacing(#"\bsk-[A-Za-z0-9_-]{8,}\b"#, in: safe, with: "[REDACTED]")
            // Remove every URL query/fragment, rather than guessing which
            // parameter names a future sign-in service uses for credentials.
            safe = replacing(#"((?:https?|wss?)://[^\s<>\"'?#]+)[?#][^\s<>\"']*"#, in: safe, with: "$1")
            safe = replacing(#"((?:https?|wss?)://)[^\s/@]+@"#, in: safe, with: "$1[REDACTED]@")
            return safe
        }.joined(separator: "\n")
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return expression.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: replacement
        )
    }
}
