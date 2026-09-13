import Foundation

struct LimitWindow: Codable, Equatable {
    var usedPercent: Double
    var windowDurationMins: Int
    var resetsAt: Date

    var windowLabel: String {
        switch windowDurationMins {
        case ..<60: return "\(windowDurationMins) 分钟窗口"
        case ..<1440: return "\(windowDurationMins / 60) 小时窗口"
        default:
            let days = windowDurationMins / 1440
            return days == 7 ? "每周窗口" : "\(days) 天窗口"
        }
    }
}

struct ResetCredit: Codable, Equatable {
    var id: String?
    var title: String
    var status: String
    var expiresAt: Date?
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var planType: String?
    var accountId: String?
    var accountEmail: String?
    var primary: LimitWindow?
    var secondary: LimitWindow?
    var extras: [NamedWindow]
    var resetCredits: [ResetCredit]
    var reachedType: String?

    struct NamedWindow: Codable, Equatable {
        var id: String
        var label: String
        var window: LimitWindow
    }

    static let empty = UsageSnapshot(
        fetchedAt: .distantPast, planType: nil, accountId: nil, accountEmail: nil,
        primary: nil, secondary: nil, extras: [], resetCredits: [], reachedType: nil
    )

    var isStale: Bool { fetchedAt == .distantPast }
}

enum UsageFormat {
    static func countdown(to date: Date, now: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSince(now).rounded()))
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60, s = secs % 60
        if d > 0 { return "\(d)天\(h)小时" }
        if h > 0 { return "\(h)小时\(m)分" }
        if m > 0 { return "\(m)分\(s)秒" }
        return "\(s)秒"
    }

    static func clock(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    static func countdownClock(to date: Date, now: Date) -> String {
        clock(max(0, Int(date.timeIntervalSince(now).rounded())))
    }

    static func absolute(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return "今天 \(f.string(from: date))"
        }
        if cal.isDateInTomorrow(date) {
            f.dateFormat = "HH:mm"
            return "明天 \(f.string(from: date))"
        }
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }

    static func timeOfDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
