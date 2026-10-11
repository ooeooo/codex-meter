import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
enum ProcessDiagnosticsCheck {
    static func main() {
        let diagnostics = CodexProcessDiagnostics()
        precondition(diagnostics.summary().isEmpty)
        diagnostics.append(Data("\u{001B}[31mnetwork: connection refused\u{001B}[0m\n".utf8))
        diagnostics.append(Data("Authorization: Bear".utf8))
        diagnostics.append(Data("er synthetic-credential-A\nretry: TLS handshake failed\n".utf8))
        let first = diagnostics.summary()
        precondition(first.contains("network: connection refused"))
        precondition(first.contains("retry: TLS handshake failed"))
        precondition(first.contains("[REDACTED]"))
        precondition(!first.contains("synthetic-credential-A"))
        precondition(!first.contains("\u{001B}"))

        let credentialLines = """
        authorization = synthetic-A
        BeArEr synthetic-B
        password: synthetic-C
        access_token = synthetic-D
        API key: synthetic-E
        client-secret = synthetic-F
        reading /Users/example/.codex/auth.json: synthetic-G
        server: 502 Bad Gateway
        """
        let redacted = CodexProcessDiagnostics.redact(credentialLines)
        for suffix in ["A", "B", "C", "D", "E", "F", "G"] {
            precondition(!redacted.contains("synthetic-" + suffix))
        }
        precondition(redacted.contains("server: 502 Bad Gateway"))

        let unlabeled = """
        value: eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzeW50aGV0aWMifQ.c3ludGhldGljLWp3dC1zaWduYXR1cmU
        value: sk-proj-syntheticCredential123456789
        fetch failed: https://example.invalid/usage?code=synthetic-H&state=synthetic-I
        redirect: https://example.invalid/callback#code=synthetic-J
        endpoint: https://synthetic-K:synthetic-L@example.invalid/usage
        """
        let safe = CodexProcessDiagnostics.redact(unlabeled)
        precondition(!safe.contains("eyJhbGci"))
        precondition(!safe.contains("syntheticCredential"))
        for suffix in ["H", "I", "J", "K", "L"] {
            precondition(!safe.contains("synthetic-" + suffix))
        }
        precondition(safe.contains("https://example.invalid/usage"))
        precondition(CodexProcessDiagnostics.redact("\u{001B}]8;;https://example.invalid\u{0007}TLS timeout\u{001B}]8;;\u{0007}") == "TLS timeout")

        // The credential label is outside the retained tail. Keeping a clipped
        // leading line would disclose an otherwise unrecognizable secret.
        let clipped = CodexProcessDiagnostics()
        clipped.append(Data(("password: " + String(repeating: "x", count: 9_000) + "synthetic-M").utf8))
        precondition(clipped.summary().isEmpty)
        clipped.append(Data("\nuseful: proxy connection failed\n".utf8))
        precondition(clipped.summary() == "useful: proxy connection failed")

        let manyLines = CodexProcessDiagnostics()
        for index in 0..<100 {
            manyLines.append(Data(("line-\(index): " + String(repeating: "x", count: 600) + "\n").utf8))
        }
        let bounded = manyLines.summary()
        let lines = bounded.components(separatedBy: "\n")
        precondition(lines.count == 8)
        precondition(lines.allSatisfy { $0.count <= 400 })
        precondition(lines.first?.hasPrefix("line-92:") == true)
        precondition(lines.last?.hasPrefix("line-99:") == true)
        precondition(bounded.utf8.count <= 8_192)

        let concurrent = CodexProcessDiagnostics()
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            concurrent.append(Data("complete-line-\(index)\n".utf8))
        }
        let concurrentLines = concurrent.summary().components(separatedBy: "\n")
        precondition(concurrentLines.count == 8)
        precondition(concurrentLines.allSatisfy { $0.hasPrefix("complete-line-") && Int($0.dropFirst("complete-line-".count)) != nil })
        print("Process diagnostics checks passed")
    }
}
