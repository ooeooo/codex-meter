import Foundation
#if canImport(CodexMeterCore)
import CodexMeterCore
#endif

@main
struct AppServerHandshakeCheck {
    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "app-server" {
            try runFakeServer()
            return
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let client = CodexAppServerClient(executableURL: executable)
        // Old stdout callbacks must not disconnect a replacement process.
        for _ in 0..<5 {
            let payload = try await client.readRateLimits()
            precondition(payload.snapshot.limitID == "codex")
            precondition(payload.snapshot.secondary?.remainingPercent == 56)
            await client.stop()
        }

        for (scenario, expected) in [
            ("initialize-error", CodexClientError.server("Unsupported client capabilities")),
            ("invalid-initialize", CodexClientError.invalidResponse),
            ("exit-before-initialize", CodexClientError.disconnected)
        ] {
            let failedClient = CodexAppServerClient(
                codexHome: URL(fileURLWithPath: "/tmp/codex-meter-check/" + scenario),
                executableURL: executable
            )
            do {
                _ = try await failedClient.readRateLimits()
                preconditionFailure("Rejected initialization must fail: " + scenario)
            } catch let error as CodexClientError {
                precondition(error == expected, "Unexpected initialization error: \(error)")
            }
            if scenario == "exit-before-initialize" {
                var diagnostics = await failedClient.diagnosticSummary()
                for _ in 0..<20 {
                    if diagnostics.contains("Process exit status: 47") && diagnostics.contains("synthetic invalid model provider") { break }
                    try await Task.sleep(for: .milliseconds(50))
                    diagnostics = await failedClient.diagnosticSummary()
                }
                precondition(diagnostics.contains("Process exit status: 47"))
                precondition(diagnostics.contains("synthetic invalid model provider"))
            }
            await failedClient.stop()
        }
        print("App-server handshake, initialization failure and reconnect checks passed")
    }

    private static func runFakeServer() throws {
        let scenario = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0).lastPathComponent } ?? "normal"
        var step = 0
        while let line = readLine() {
            let data = Data(line.utf8)
            guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let method = message["method"] as? String else { exit(20) }
            switch (step, method) {
            case (0, "initialize"):
                guard let id = message["id"] else { exit(21) }
                if scenario == "initialize-error" {
                    write(["id": id, "error": ["code": -32600, "message": "Unsupported client capabilities"]])
                    step = -1
                } else if scenario == "invalid-initialize" {
                    write(["id": id, "result": "invalid"])
                    step = -1
                } else if scenario == "exit-before-initialize" {
                    FileHandle.standardError.write(Data("configuration error: synthetic invalid model provider\n".utf8))
                    exit(47)
                } else {
                    write(["id": id, "result": [:]])
                    step = 1
                }
            case (1, "initialized"):
                step = 2
            case (2, "account/rateLimits/read"):
                guard let id = message["id"] else { exit(22) }
                write([
                    "id": id,
                    "result": [
                        "rateLimitsByLimitId": [
                            "codex": [
                                "limitId": "codex",
                                "planType": "prolite",
                                "secondary": [
                                    "usedPercent": 44,
                                    "windowDurationMins": 10_080,
                                    "resetsAt": 2_000_000_000
                                ]
                            ]
                        ]
                    ]
                ])
                step = 3
            default:
                // A rejected initialize reply must never be followed by a
                // ready notification or a quota request.
                exit(23)
            }
        }
    }

    private static func write(_ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
