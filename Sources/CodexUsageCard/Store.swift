import Foundation
import SwiftUI
import Combine
import UserNotifications

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot
    @Published var now = Date()
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var collapsed = false
    @Published var showSettings = false

    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.login) }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var theme: ThemeMode {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var refreshSeconds: Int {
        didSet {
            UserDefaults.standard.set(refreshSeconds, forKey: Keys.refreshSec)
            restartAutoTimer()
        }
    }
    @Published var autoUseCredit: Bool {
        didSet { UserDefaults.standard.set(autoUseCredit, forKey: Keys.autoCredit) }
    }
    @Published var usageAlerts: Bool {
        didSet { UserDefaults.standard.set(usageAlerts, forKey: Keys.alerts) }
    }
    @Published var isConsuming = false
    @Published var creditArmed = false
    @Published var toast: String?

    // 重置雷达（额外重置概率）
    @Published var radar: RadarSnapshot?
    @Published var radarError: String?
    @Published var radarConfigured = false

    private enum Keys {
        static let login = "setting.launchAtLogin"
        static let appearance = "setting.appearance"
        static let theme = "setting.theme"
        static let refreshSec = "setting.refreshSeconds"
        static let refreshLegacyMinutes = "setting.refreshMinutes"
        static let autoCredit = "setting.autoUseCredit"
        static let alerts = "setting.usageAlerts"
        static let lastTier = "alert.lastTier"
    }

    private var refreshTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var autoTimer: Timer?
    private var toastTask: Task<Void, Never>?
    private var disarmTask: Task<Void, Never>?

    var refreshLabel: String {
        refreshSeconds < 60 ? "每 \(refreshSeconds) 秒自动刷新" : "每 \(refreshSeconds / 60) 分钟自动刷新"
    }

    init() {
        snapshot = SnapshotCache.load() ?? .empty
        let defaults = UserDefaults.standard
        launchAtLogin = defaults.object(forKey: Keys.login) as? Bool ?? LoginItem.isEnabled
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        theme = ThemeMode(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .auto
        if let seconds = defaults.object(forKey: Keys.refreshSec) as? Int {
            refreshSeconds = seconds
        } else if let minutes = defaults.object(forKey: Keys.refreshLegacyMinutes) as? Int {
            refreshSeconds = minutes * 60
        } else {
            refreshSeconds = 60
        }
        autoUseCredit = defaults.object(forKey: Keys.autoCredit) as? Bool ?? false
        usageAlerts = defaults.object(forKey: Keys.alerts) as? Bool ?? true
        lastTier = defaults.object(forKey: Keys.lastTier) as? Int ?? -1
        radar = RadarCache.load()
        radarConfigured = RadarProvider.hasAPIKey()
    }

    /// 通用 codex 周窗口（10080 分钟）：优先 secondary，其次 extras
    private var weeklyWindow: LimitWindow? {
        if let s = snapshot.secondary, s.windowDurationMins == 10080 { return s }
        return snapshot.extras.first(where: { $0.window.windowDurationMins == 10080 })?.window
    }

    var radarPersonal: (percent: Double, reason: String)? {
        guard let radar else { return nil }
        return radar.personalProbability(weeklyResetsAt: weeklyWindow?.resetsAt, now: now)
    }

    /// 雷达服务端限额：每账户 30 次 / 10 分钟，轮询必须 ≥10 分钟
    private static let radarMinInterval: TimeInterval = 600
    private var lastRadarFetch = Date.distantPast
    private var radarTask: Task<Void, Never>?

    func refreshRadar(force: Bool = false) {
        guard radarTask == nil else { return }
        guard radarConfigured else { return }
        if !force, Date().timeIntervalSince(lastRadarFetch) < Self.radarMinInterval { return }
        lastRadarFetch = Date()
        radarTask = Task { [weak self] in
            do {
                let snapshot = try await RadarProvider.fetchOverview()
                guard !Task.isCancelled else { return }
                self?.radar = snapshot
                self?.radarError = nil
                RadarCache.save(snapshot)
                CardLog.write("雷达刷新成功：额外概率 \(Int(snapshot.codexProbability.rounded()))%")
            } catch {
                guard let message = (error as? RadarError)?.errorDescription ?? (error as? LocalizedError)?.errorDescription,
                      !Task.isCancelled else { return }
                self?.radarError = message
                CardLog.write("雷达刷新失败：\(message)")
            }
            self?.radarTask = nil
        }
    }

    func saveRadarKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RadarKeychain.isValidKey(trimmed) else { return false }
        RadarKeychain.save(trimmed)
        radarConfigured = true
        radarError = nil
        lastRadarFetch = .distantPast
        refreshRadar(force: true)
        return true
    }

    func clearRadarKey() {
        RadarKeychain.delete()
        radarConfigured = false
        radar = nil
        radarError = nil
        RadarCache.clear()
    }

    private var lastTier: Int

    private func handleTierCrossing(_ fresh: UsageSnapshot) {
        guard let pct = fresh.primary?.usedPercent else { return }
        let newTier = UsagePalette.tierIndex(for: pct)
        defer { UserDefaults.standard.set(newTier, forKey: Keys.lastTier) }
        let previousTier = lastTier
        lastTier = newTier
        guard previousTier >= 0, newTier > previousTier, usageAlerts else { return }
        let messages = [
            1: "5 小时窗口已用 \(Int(pct.rounded()))%，进入注意区（≥50%）",
            2: "5 小时窗口已用 \(Int(pct.rounded()))%，进入警告区（≥80%）",
            3: "5 小时窗口已用 \(Int(pct.rounded()))%，额度即将耗尽（≥95%）",
        ]
        guard let message = messages[newTier] else { return }
        CardLog.write("用量告警：\(message)")
        showToast("⚠️ \(message)")
        notify("⚠️ \(message)")
    }

    func fireTestAlert() {
        let pct = Int((snapshot.primary?.usedPercent ?? 0).rounded())
        let message = "5 小时窗口已用 \(pct)%（测试告警，档位：\(UsagePalette.tierName(UsagePalette.tierIndex(for: snapshot.primary?.usedPercent ?? 0)))）"
        CardLog.write("用量告警：\(message)")
        showToast("⚠️ \(message)")
        notify("⚠️ \(message)")
    }

    func start() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        restartAutoTimer()
        refresh()
    }

    func stop() {
        tickTimer?.invalidate()
        autoTimer?.invalidate()
        tickTimer = nil
        autoTimer = nil
    }

    private var lastZeroRefresh = Date.distantPast

    private func tick() {
        now = Date()
        guard let resetsAt = snapshot.primary?.resetsAt else { return }
        if now >= resetsAt, now.timeIntervalSince(lastZeroRefresh) > 30 {
            lastZeroRefresh = now
            refresh()
        }
    }

    private func restartAutoTimer() {
        autoTimer?.invalidate()
        autoTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            do {
                let fresh = try await withThrowingTaskGroup(of: UsageSnapshot.self) { group in
                    group.addTask { try await CodexProvider.fetch() }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 45_000_000_000)
                        throw UsageError.protocolTimeout
                    }
                    guard let first = try await group.next() else { throw UsageError.protocolTimeout }
                    group.cancelAll()
                    return first
                }
                guard !Task.isCancelled else { return }
                self?.snapshot = fresh
                self?.errorMessage = nil
                SnapshotCache.save(fresh)
                self?.handleTierCrossing(fresh)
                self?.maybeAutoConsume(fresh)
                self?.refreshRadar()
            } catch {
                self?.errorMessage = error.localizedDescription
                CardLog.write("用量刷新失败：\(error.localizedDescription)")
            }
            self?.isRefreshing = false
            self?.refreshTask = nil
        }
    }

    func armCredit() {
        CardLog.write("用户点击「立即使用」，进入确认态")
        creditArmed = true
        disarmTask?.cancel()
        disarmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.creditArmed = false
        }
    }

    func cancelCredit() {
        CardLog.write("用户取消使用重置券")
        disarmTask?.cancel()
        creditArmed = false
    }

    func consumeCredit() {
        guard !isConsuming else { return }
        guard let credit = snapshot.resetCredits.first, let creditId = credit.id else {
            CardLog.write("消耗失败：快照里没有带 id 的可用券")
            showToast("没有可用的重置券")
            return
        }
        CardLog.write("开始消耗重置券 \(creditId)")
        creditArmed = false
        isConsuming = true
        Task { [weak self] in
            do {
                var fresh = try await CodexProvider.consumeAndReread(creditId: creditId)
                if fresh.accountEmail == nil { fresh.accountEmail = self?.snapshot.accountEmail }
                self?.snapshot = fresh
                self?.errorMessage = nil
                SnapshotCache.save(fresh)
                CardLog.write("消耗成功，额度已重读")
                self?.showToast("5 小时额度已刷新")
                self?.notify("5 小时额度已成功刷新")
            } catch {
                CardLog.write("消耗失败：\(error.localizedDescription)")
                self?.showToast("刷新失败：\(error.localizedDescription)")
            }
            self?.isConsuming = false
        }
    }

    private func maybeAutoConsume(_ fresh: UsageSnapshot) {
        guard autoUseCredit, !isConsuming else { return }
        let exhausted = fresh.reachedType != nil || (fresh.primary?.usedPercent ?? 0) >= 100
        guard exhausted, fresh.resetCredits.contains(where: { $0.id != nil }) else { return }
        consumeCredit()
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func notify(_ body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Codex 用量"
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        if let failure = LoginItem.set(enabled) {
            launchAtLogin = LoginItem.isEnabled
            errorMessage = "开机自启设置失败：\(failure)"
        }
    }

    var statusTint: Color {
        // 数据/状态元素：安全区用主题色，≥50% 起档位色接管（预警优先）
        if let pct = snapshot.primary?.usedPercent, UsagePalette.tierIndex(for: pct) >= 1 {
            return UsagePalette.tint(for: pct)
        }
        if let fixed = theme.color { return fixed }
        guard let pct = snapshot.primary?.usedPercent else { return .secondary }
        return UsagePalette.tint(for: pct)
    }

    var brandTint: Color {
        // 品牌元素（PLUS 徽章、重置券横幅）：主题色常显，不随用量变红
        theme.color ?? statusTint
    }
}

enum CardLog {
    static func write(_ message: String) {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/CodexUsageCard.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "MM-dd HH:mm:ss"
        let line = "\(stamp.string(from: Date())) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

enum UsagePalette {
    /// 用量警示统一使用三档固定颜色，不受个人主题色影响。
    static func alertTint(for percent: Double?) -> Color {
        guard let percent else { return .secondary }
        switch percent {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }

    static func tierIndex(for percent: Double) -> Int {
        switch percent {
        case ..<50: return 0
        case ..<80: return 1
        case ..<95: return 2
        default: return 3
        }
    }

    static func tierName(_ tier: Int) -> String {
        ["安全", "注意", "警告", "危险"][tier]
    }

    static func tint(for percent: Double) -> Color {
        switch percent {
        case ..<50: return Color(red: 0.32, green: 0.82, blue: 0.62)
        case ..<80: return Color(red: 1.00, green: 0.72, blue: 0.30)
        case ..<95: return Color(red: 1.00, green: 0.55, blue: 0.24)
        default: return Color(red: 1.00, green: 0.36, blue: 0.40)
        }
    }
}
