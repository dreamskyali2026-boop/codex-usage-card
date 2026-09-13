import Foundation

enum UsageError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case protocolTimeout
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 codex CLI"
        case .launchFailed(let m): return "启动 app-server 失败：\(m)"
        case .protocolTimeout: return "app-server 响应超时"
        case .badResponse(let m): return "响应异常：\(m)"
        }
    }
}

enum CodexBin {
    private static let cacheKey = "resolvedCodexBin"

    static func resolve() -> String? {
        if let env = ProcessInfo.processInfo.environment["CODEX_BIN"],
           FileManager.default.isExecutableFile(atPath: env) { return env }
        if let cached = UserDefaults.standard.string(forKey: cacheKey),
           FileManager.default.isExecutableFile(atPath: cached) { return cached }

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/bin/codex",
        ]
        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            UserDefaults.standard.set(hit, forKey: cacheKey)
            return hit
        }
        if let viaShell = shellResolve() {
            UserDefaults.standard.set(viaShell, forKey: cacheKey)
            return viaShell
        }
        return nil
    }

    private static func shellResolve() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v codex"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}

struct CodexProvider {
    private struct WireWindow: Decodable {
        let usedPercent: Double?
        let windowDurationMins: Int?
        let resetsAt: Double?
    }
    private struct WireLimit: Decodable {
        let limitId: String?
        let limitName: String?
        let primary: WireWindow?
        let secondary: WireWindow?
        let planType: String?
        let rateLimitReachedType: String?
    }
    private struct WireCredits: Decodable {
        let availableCount: Int?
        struct Item: Decodable { let id: String?; let title: String?; let status: String?; let expiresAt: Double? }
        let credits: [Item]?
    }
    private struct WireResult: Decodable {
        let rateLimits: WireLimit?
        let rateLimitsByLimitId: [String: WireLimit]?
        let rateLimitResetCredits: WireCredits?
        let accountId: String?
    }
    private struct WireAccountResult: Decodable {
        struct Account: Decodable { let email: String? }
        let account: Account?
    }

    static func fetch() async throws -> UsageSnapshot {
        guard let bin = CodexBin.resolve() else { throw UsageError.codexNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["app-server"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { throw UsageError.launchFailed(error.localizedDescription) }
        defer { process.terminate() }

        let writer = stdin.fileHandleForWriting
        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            writer.write(data)
            writer.write(Data("\n".utf8))
        }

        send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "codex-usage-card", "title": "Codex 用量", "version": "1.0.0"]],
        ])

        var result: UsageSnapshot?
        var accountEmail: String?
        var gotAccount = false
        var sawInit = false
        let deadline = Date().addingTimeInterval(30)

        for try await line in stdout.fileHandleForReading.bytes.lines {
            if Date() > deadline { break }
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let id = message["id"] as? Int else { continue }

            if id == 1 {
                guard message["result"] != nil else { throw UsageError.badResponse("initialize 失败") }
                sawInit = true
                send(["jsonrpc": "2.0", "method": "notifications/initialized"])
                send(["jsonrpc": "2.0", "id": 2, "method": "account/read", "params": [String: Any]()])
                send(["jsonrpc": "2.0", "id": 3, "method": "account/rateLimits/read", "params": [String: Any]()])
            } else if id == 2 {
                if let payload = message["result"] {
                    let data = try JSONSerialization.data(withJSONObject: payload)
                    accountEmail = (try? JSONDecoder().decode(WireAccountResult.self, from: data))?.account?.email
                }
                gotAccount = true
                if result != nil { break }
            } else if id == 3 {
                guard let payload = message["result"] else {
                    let err = message["error"] as? [String: Any]
                    throw UsageError.badResponse((err?["message"] as? String) ?? "rateLimits/read 失败")
                }
                let data = try JSONSerialization.data(withJSONObject: payload)
                let wire = try JSONDecoder().decode(WireResult.self, from: data)
                result = Self.map(wire, email: accountEmail)
                if gotAccount { break }
            }
        }

        guard sawInit else { throw UsageError.protocolTimeout }
        guard let snapshot = result else { throw UsageError.protocolTimeout }
        return snapshot
    }

    static func consumeAndReread(creditId: String, limitId: String = "codex") async throws -> UsageSnapshot {
        guard let bin = CodexBin.resolve() else { throw UsageError.codexNotFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["app-server"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch { throw UsageError.launchFailed(error.localizedDescription) }
        defer { process.terminate() }

        let writer = stdin.fileHandleForWriting
        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            writer.write(data)
            writer.write(Data("\n".utf8))
        }

        send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "codex-usage-card", "title": "Codex 用量", "version": "1.0.0"]],
        ])

        var result: UsageSnapshot?
        var sawInit = false
        let deadline = Date().addingTimeInterval(30)

        for try await line in stdout.fileHandleForReading.bytes.lines {
            if Date() > deadline { break }
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let id = message["id"] as? Int else { continue }

            if id == 1 {
                guard message["result"] != nil else { throw UsageError.badResponse("initialize 失败") }
                sawInit = true
                send(["jsonrpc": "2.0", "method": "notifications/initialized"])
                send([
                    "jsonrpc": "2.0", "id": 2, "method": "account/rateLimitResetCredit/consume",
                    "params": ["creditId": creditId, "limitId": limitId],
                ])
            } else if id == 2 {
                guard message["result"] != nil else {
                    let err = message["error"] as? [String: Any]
                    throw UsageError.badResponse((err?["message"] as? String) ?? "重置券消耗失败")
                }
                send(["jsonrpc": "2.0", "id": 3, "method": "account/rateLimits/read", "params": [String: Any]()])
            } else if id == 3 {
                guard let payload = message["result"] else {
                    let err = message["error"] as? [String: Any]
                    throw UsageError.badResponse((err?["message"] as? String) ?? "rateLimits/read 失败")
                }
                let data = try JSONSerialization.data(withJSONObject: payload)
                let wire = try JSONDecoder().decode(WireResult.self, from: data)
                result = Self.map(wire, email: nil)
                break
            }
        }

        guard sawInit else { throw UsageError.protocolTimeout }
        guard let snapshot = result else { throw UsageError.protocolTimeout }
        return snapshot
    }

    private static func map(_ wire: WireResult, email: String?) -> UsageSnapshot {
        func window(_ w: WireWindow?) -> LimitWindow? {
            guard let w, let pct = w.usedPercent, let mins = w.windowDurationMins, let at = w.resetsAt else { return nil }
            return LimitWindow(usedPercent: pct, windowDurationMins: mins, resetsAt: Date(timeIntervalSince1970: at))
        }

        let main = wire.rateLimits
        var extras: [UsageSnapshot.NamedWindow] = []
        for (id, limit) in (wire.rateLimitsByLimitId ?? [:]) where id != "codex" {
            if let w = window(limit.primary) {
                extras.append(.init(id: id, label: displayName(id: id, fallback: limit.limitName), window: w))
            }
        }
        extras.sort { $0.window.resetsAt < $1.window.resetsAt }

        let credits = (wire.rateLimitResetCredits?.credits ?? [])
            .filter { ($0.status ?? "available") == "available" }
            .map { ResetCredit(id: $0.id, title: $0.title ?? "重置券", status: $0.status ?? "available",
                               expiresAt: $0.expiresAt.map { Date(timeIntervalSince1970: $0) }) }

        return UsageSnapshot(
            fetchedAt: Date(),
            planType: main?.planType,
            accountId: wire.accountId,
            accountEmail: email,
            primary: window(main?.primary),
            secondary: window(main?.secondary),
            extras: extras,
            resetCredits: credits,
            reachedType: main?.rateLimitReachedType
        )
    }

    private static func displayName(id: String, fallback: String?) -> String {
        switch id {
        case "base_model_inference": return "GPT 储备额度"
        default: return fallback ?? id
        }
    }
}

enum SnapshotCache {
    private static var url: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CodexUsageCard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snapshot.json")
    }

    static func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
