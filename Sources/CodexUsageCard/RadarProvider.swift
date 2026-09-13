import Foundation
import Security

// 重置雷达会员 API（https://api.tangka.online/radar-api/member/v1）
// 协议依据：重置雷达悬浮框使用指南（2026-09-10）与官方 reset-rader 仓库 api-client.mjs

enum RadarError: LocalizedError {
    case keyMissing
    case keyInvalid
    case inactiveMembership
    case rateLimited(retryAfterSeconds: Int)
    case staleData
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .keyMissing: return "未配置重置雷达 API Key"
        case .keyInvalid: return "API Key 无效或已撤销，请到小程序「雷达会员 → 管理 API Key」重新获取"
        case .inactiveMembership: return "重置雷达长期会员权益无效（月度会员不含 API 权益）"
        case .rateLimited(let s): return "触发雷达限流，\(s) 秒后自动重试"
        case .staleData: return "雷达数据已超过 2 小时，拒绝展示"
        case .badResponse(let m): return "雷达响应异常：\(m)"
        case .network(let m): return "雷达请求失败：\(m)"
        }
    }

    var retryAfterSeconds: Int? {
        if case .rateLimited(let s) = self { return s }
        return nil
    }
}

struct RadarSnapshot: Codable, Equatable {
    var generatedAt: Date
    var codexProbability: Double

    private struct Wire: Decodable {
        let naturalCycle: String?
        let generatedAt: String?
        let platforms: [Platform]?
        struct Platform: Decodable {
            let id: String?
            let probability: Double?
        }
    }

    static func parse(data: Data, now: Date = Date()) throws -> RadarSnapshot {
        let wire: Wire
        do { wire = try JSONDecoder().decode(Wire.self, from: data) }
        catch { throw RadarError.badResponse("JSON 解析失败") }
        guard wire.naturalCycle == "exclude" else {
            throw RadarError.badResponse("服务端未确认 naturalCycle=exclude")
        }
        guard let generated = wire.generatedAt,
              let date = ISO8601DateFormatter.flexible.date(from: generated) else {
            throw RadarError.badResponse("缺少 generatedAt")
        }
        // 未来偏移超过 5 分钟视为时钟异常，超过 2 小时视为过期
        let age = now.timeIntervalSince(date)
        guard age >= -300, age <= 2 * 3600 else { throw RadarError.staleData }
        guard let codex = wire.platforms?.first(where: { $0.id == "codex" }),
              let probability = codex.probability, probability >= 0, probability <= 100 else {
            throw RadarError.badResponse("缺少 codex 平台概率")
        }
        return RadarSnapshot(generatedAt: date, codexProbability: probability)
    }

    /// 未来 24 小时的个人重置概率：周窗口 24 小时内到期 → 100%（自然周重置）；
    /// 否则取雷达的额外重置概率。周窗口缺失/已过期 → nil（不可用，不是 0）。
    func personalProbability(weeklyResetsAt: Date?, now: Date) -> (percent: Double, reason: String)? {
        guard let reset = weeklyResetsAt, reset > now else { return nil }
        if reset.timeIntervalSince(now) <= 24 * 3600 {
            return (100, "周额度 24 小时内自然重置")
        }
        return (codexProbability, "雷达预测的额外重置概率")
    }
}

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

enum RadarKeychain {
    private static let service = "CodexUsageCard"
    private static let account = "reset-radar-api-key"
    static let keyPattern = try! NSRegularExpression(pattern: "^rr_live_[A-Za-z0-9_-]{12}_[A-Za-z0-9_-]{43}$")

    static func isValidKey(_ key: String) -> Bool {
        let range = NSRange(key.startIndex..., in: key)
        return keyPattern.firstMatch(in: key, range: range) != nil
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == noErr, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(attributes as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum RadarProvider {
    static let apiBase = "https://api.tangka.online/radar-api/member/v1"
    private static let retryDeadlineKey = "radar.retryDeadline"
    private static let requestTimeout: TimeInterval = 20

    static var retryDeadline: Date {
        get {
            let t = UserDefaults.standard.double(forKey: retryDeadlineKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
        }
        set {
            UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: retryDeadlineKey)
        }
    }

    static func hasAPIKey() -> Bool {
        guard let key = RadarKeychain.load() else { return false }
        return RadarKeychain.isValidKey(key)
    }

    static func fetchOverview(now: Date = Date()) async throws -> RadarSnapshot {
        guard Date() >= retryDeadline else {
            let s = Int(ceil(retryDeadline.timeIntervalSinceNow))
            throw RadarError.rateLimited(retryAfterSeconds: max(s, 1))
        }
        guard let key = RadarKeychain.load() else { throw RadarError.keyMissing }
        guard RadarKeychain.isValidKey(key) else { throw RadarError.keyInvalid }

        var request = URLRequest(url: URL(string: "\(apiBase)/overview?naturalCycle=exclude")!)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RadarError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        func retrySeconds() -> Int {
            let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
            let headerSecs = header.flatMap { Int($0) }
            struct Err: Decodable { let retryAfterSeconds: Double? }
            let bodySecs = (try? JSONDecoder().decode(Err.self, from: data))?.retryAfterSeconds.map { Int(ceil($0)) }
            return max(headerSecs ?? 0, bodySecs ?? 0)
        }

        switch status {
        case 200:
            return try RadarSnapshot.parse(data: data, now: now)
        case 401:
            throw RadarError.keyInvalid
        case 403:
            throw RadarError.inactiveMembership
        case 429:
            let s = max(retrySeconds(), 60)
            retryDeadline = Date().addingTimeInterval(TimeInterval(s))
            throw RadarError.rateLimited(retryAfterSeconds: s)
        default:
            throw RadarError.badResponse("HTTP \(status)")
        }
    }
}

enum RadarCache {
    private static var url: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CodexUsageCard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("radar.json")
    }

    static func save(_ snapshot: RadarSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> RadarSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RadarSnapshot.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
