import SwiftUI
import ServiceManagement

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"
    var id: String { rawValue }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case auto = "自动"
    case mint = "薄荷"
    case blue = "天蓝"
    case purple = "紫罗兰"
    case orange = "暖橙"

    var id: String { rawValue }

    var color: Color? {
        switch self {
        case .auto: return nil
        case .mint: return Color(red: 0.32, green: 0.82, blue: 0.62)
        case .blue: return Color(red: 0.30, green: 0.62, blue: 0.95)
        case .purple: return Color(red: 0.62, green: 0.44, blue: 0.95)
        case .orange: return Color(red: 1.00, green: 0.60, blue: 0.24)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    var onClose: () -> Void = {}

    private let refreshOptions: [(seconds: Int, label: String)] = [
        (15, "15 秒"), (30, "30 秒"), (60, "1 分"), (300, "5 分"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            loginRow
            autoCreditRow
            alertRow
            radarKeyBlock
            appearanceBlock
            themeBlock
            refreshBlock
            footerNote
        }
        .frame(width: 324)
        .padding(18)
    }

    @State private var radarKeyInput = ""
    @State private var radarKeySaveFailed = false
    @State private var radarKeyEditing = false

    private var radarKeyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("重置雷达 API Key", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline)
                Spacer()
                if store.radarConfigured {
                    Text("已配置")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            if store.radarConfigured && !radarKeyEditing {
                HStack(spacing: 8) {
                    Button("修改 Key") { radarKeyEditing = true }
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(store.brandTint))
                        .buttonStyle(.plain)
                    Button("清除 Key") { store.clearRadarKey() }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    Button("立即刷新雷达") { store.refreshRadar(force: true) }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.plain)
                    Spacer()
                }
            }
            if !store.radarConfigured || radarKeyEditing {
                if radarKeyEditing {
                    Text("旧 Key 不会回显，粘贴新 Key 覆盖保存。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                SecureField("rr_live_…（粘贴后点保存）", text: $radarKeyInput)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    Button {
                        if store.saveRadarKey(radarKeyInput) {
                            radarKeyInput = ""
                            radarKeySaveFailed = false
                            radarKeyEditing = false
                        } else {
                            radarKeySaveFailed = true
                        }
                    } label: {
                        Text(radarKeyEditing ? "保存新 Key" : "保存并连接")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(store.brandTint))
                    }
                    .buttonStyle(.plain)
                    .disabled(radarKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if radarKeyEditing {
                        Button("取消") {
                            radarKeyInput = ""
                            radarKeyEditing = false
                            radarKeySaveFailed = false
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Text(radarKeySaveFailed
                 ? "Key 格式不对：应为 rr_live_ 开头的长串，去小程序「雷达会员 → 管理 API Key」复制完整 Key"
                 : "在重置雷达小程序「雷达会员 → 管理 API Key」获取；仅长期会员可用。Key 保存在本机钥匙串，用于查询未来 24 小时的额外重置概率（每 10 分钟最多查询一次）。")
                .font(.caption2)
                .foregroundStyle(radarKeySaveFailed ? .red : .secondary)
        }
    }

    private var alertRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("用量分档提醒", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                Spacer()
                Toggle("用量分档提醒", isOn: $store.usageAlerts)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            Text("5 小时窗口向上跨越 50% / 80% / 95% 时弹系统通知和卡片提示；颜色同步切换：安全(绿) → 注意(黄) → 警告(橙) → 危险(红)。每档只提醒一次。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("设置")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.primary.opacity(0.08)))
                    .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("返回卡片")
        }
    }

    private var loginRow: some View {
        HStack {
            Label("开机自启", systemImage: "power")
                .font(.subheadline)
            Spacer()
            Toggle("开机自启", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
    }

    private var autoCreditRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("额度耗尽时自动用券", systemImage: "bolt.fill")
                    .font(.subheadline)
                Spacer()
                Toggle("额度耗尽时自动用券", isOn: $store.autoUseCredit)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            Text("5 小时额度用尽且账户有重置券时，自动消耗一张并弹窗提醒。券很稀缺，默认关闭。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var appearanceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("外观", systemImage: "circle.lefthalf.filled")
                .font(.subheadline)
            Picker("外观", selection: $store.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var themeBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("主题色", systemImage: "paintpalette")
                .font(.subheadline)
            HStack(spacing: 12) {
                ForEach(ThemeMode.allCases) { theme in
                    themeDot(theme)
                }
                Spacer()
            }
        }
    }

    private func themeDot(_ theme: ThemeMode) -> some View {
        let selected = store.theme == theme
        return Button {
            store.theme = theme
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if theme == .auto {
                        Circle()
                            .strokeBorder(.primary.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Image(systemName: "a")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                            )
                    } else {
                        Circle()
                            .fill(theme.color ?? .mint)
                            .frame(width: 20, height: 20)
                    }
                    if selected {
                        Circle()
                            .strokeBorder(.primary.opacity(0.8), lineWidth: 2)
                            .frame(width: 27, height: 27)
                    }
                }
                .frame(width: 27, height: 27)
                Text(theme.rawValue)
                    .font(.caption2)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(theme.rawValue)
    }

    private var refreshBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("自动刷新间隔", systemImage: "arrow.clockwise")
                .font(.subheadline)
            Picker("自动刷新间隔", selection: $store.refreshSeconds) {
                ForEach(refreshOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("间隔越短越实时；15/30 秒会频繁启动 codex 子进程，开销略增。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footerNote: some View {
        Text("数据经本机 codex app-server 读取，仅在此显示，不上传。")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
