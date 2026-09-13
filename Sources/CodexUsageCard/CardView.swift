import SwiftUI

enum RenderMode {
    static var useGlass = true
}

struct CardView: View {
    @ObservedObject var store: UsageStore
    var onRefresh: () -> Void = {}
    var onToggleCollapse: () -> Void = {}
    var onClose: () -> Void = {}

    private let cardWidth: CGFloat = 324

    var body: some View {
        surface
            .overlay(alignment: .top) {
                if let toast = store.toast {
                    Text(toast)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.regularMaterial))
                        .overlay(Capsule().strokeBorder(store.statusTint.opacity(0.55), lineWidth: 1))
                        .foregroundStyle(store.statusTint)
                        .offset(y: -16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.spring(duration: 0.35), value: store.toast)
    }

    @ViewBuilder
    private var surface: some View {
        let radius: CGFloat = store.collapsed ? 24 : 28
        if RenderMode.useGlass {
            cardBody
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
                .clipShape(.rect(cornerRadius: radius, style: .continuous))
        } else {
            cardBody
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.white.opacity(0.30), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        if store.showSettings {
            SettingsView(store: store, onClose: { store.showSettings = false })
        } else if store.collapsed {
            collapsedPill
        } else {
            content
                .frame(width: cardWidth)
                .padding(18)
        }
    }

    private var marqueeItems: [(text: String, color: Color)] {
        var items: [(String, Color)] = []
        if let primary = store.snapshot.primary {
            items.append((
                "已用 \(Int(primary.usedPercent.rounded()))% · 5小时窗口 \(UsageFormat.countdownClock(to: primary.resetsAt, now: store.now)) 后重置",
                store.statusTint
            ))
        }
        if let secondary = store.snapshot.secondary {
            let pct = Int(secondary.usedPercent.rounded())
            items.append((
                "每周窗口 已用 \(pct)% · 剩 \(100 - pct)% · \(UsageFormat.countdown(to: secondary.resetsAt, now: store.now)) 后重置",
                UsagePalette.tint(for: secondary.usedPercent)
            ))
        }
        for extra in store.snapshot.extras {
            let pct = Int(extra.window.usedPercent.rounded())
            items.append((
                "\(extra.label) 已用 \(pct)% · 剩 \(100 - pct)% · \(UsageFormat.countdown(to: extra.window.resetsAt, now: store.now)) 后重置",
                UsagePalette.tint(for: extra.window.usedPercent)
            ))
        }
        if !store.snapshot.resetCredits.isEmpty {
            items.append((
                "⚡ \(store.snapshot.resetCredits.count) 张重置券可用 · 展开卡片点「立即使用」可清零额度",
                store.brandTint
            ))
        }
        if let personal = store.radarPersonal {
            items.append((
                "🎯 未来 24h 重置概率 \(Int(personal.percent.rounded()))%（\(personal.reason)）· \(UsageFormat.timeOfDay(store.radar?.generatedAt ?? Date())) 更新",
                store.brandTint
            ))
        }
        return items
    }

    private var marquee: some View {
        let items = marqueeItems
        let slot = items.isEmpty ? 0 : Int(Date().timeIntervalSinceReferenceDate / 5) % items.count
        let entry = items.isEmpty ? (text: "等待数据…", color: Color.secondary) : items[slot]
        return ZStack {
            Text(entry.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(entry.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(slot)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .animation(.easeInOut(duration: 0.45), value: slot)
        .clipped()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.statusTint)
                .frame(width: 8, height: 8)
            marquee
            iconButton("chevron.up", size: 22, action: onToggleCollapse, help: "展开卡片")
            iconButton("xmark", size: 22, action: onClose, help: "隐藏卡片")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 316)
        .help(primaryHelp)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            hero
            divider
            secondaryRows
            radarRow
            if store.creditArmed {
                creditConfirm
            } else if !store.snapshot.resetCredits.isEmpty {
                creditsBanner
            }
            footer
        }
    }

    private var creditConfirm: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("消耗 1 张重置券，立即重置 5 小时与每周额度？")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                Button {
                    store.cancelCredit()
                } label: {
                    Text("取消")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.primary.opacity(0.10)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    store.consumeCredit()
                } label: {
                    Text("确认使用")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(store.statusTint))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(store.statusTint.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(store.statusTint.opacity(0.45), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.statusTint)
                .frame(width: 8, height: 8)
                .shadow(color: store.statusTint.opacity(0.8), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex 用量")
                    .font(.headline)
                if let email = store.snapshot.accountEmail {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(email)
                }
            }
            Spacer(minLength: 4)
            if let plan = store.snapshot.planType {
                Text(plan.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(store.brandTint.opacity(0.18)))
                    .foregroundStyle(store.brandTint)
            }
            refreshButton
            iconButton("gearshape", size: 22, action: { store.showSettings = true }, help: "设置")
            iconButton("minus", size: 22, action: onToggleCollapse, help: "收起到顶部菜单栏")
            iconButton("xmark", size: 22, action: onClose, help: "隐藏卡片")
        }
    }

    private var refreshButton: some View {
        iconButton("arrow.clockwise", size: 24, action: onRefresh, help: "立即刷新")
            .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
            .animation(store.isRefreshing
                       ? .linear(duration: 1.2).repeatForever(autoreverses: false)
                       : .default,
                       value: store.isRefreshing)
    }

    private func iconButton(_ symbol: String, size: CGFloat,
                            action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .frame(width: size, height: size)
                .background(Circle().fill(.primary.opacity(0.08)))
                .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var primaryHelp: String {
        guard let window = store.snapshot.primary else { return "等待数据…" }
        let pct = Int(window.usedPercent.rounded())
        let tier = UsagePalette.tierName(UsagePalette.tierIndex(for: window.usedPercent))
        return "5 小时滚动窗口：已用 \(pct)%（当前会话消耗的额度占比），档位「\(tier)」，"
            + "\(UsageFormat.countdown(to: window.resetsAt, now: store.now)) 后整窗重置为 0%"
    }

    private var hero: some View {
        HStack(spacing: 18) {
            RingGauge(percent: store.snapshot.primary?.usedPercent ?? 0,
                      tint: UsagePalette.alertTint(for: store.snapshot.primary?.usedPercent))
                .frame(width: 92, height: 92)
                .help(primaryHelp)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.snapshot.primary?.windowLabel ?? "5 小时窗口")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let window = store.snapshot.primary {
                    Text(UsageFormat.countdownClock(to: window.resetsAt, now: store.now))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .help(primaryHelp)
                    Text("重置于 \(UsageFormat.absolute(window.resetsAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("重置的具体时间点：\(UsageFormat.absolute(window.resetsAt))，到点后额度自动恢复")
                } else {
                    Text("--:--:--")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(store.errorMessage ?? "等待数据…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.10))
            .frame(height: 1)
    }

    private var secondaryRows: some View {
        VStack(spacing: 12) {
            if let secondary = store.snapshot.secondary {
                LimitRow(label: secondary.windowLabel, window: secondary, now: store.now)
            }
            ForEach(store.snapshot.extras, id: \.id) { extra in
                LimitRow(label: extra.label, window: extra.window, now: store.now)
            }
            if store.snapshot.secondary == nil && store.snapshot.extras.isEmpty {
                Text("暂无其他额度窗口")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var radarRow: some View {
        if store.radarConfigured {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(store.brandTint)
                    Text("未来 24 小时重置概率")
                        .font(.subheadline)
                    Spacer(minLength: 4)
                    if let personal = store.radarPersonal {
                        Text("\(Int(personal.percent.rounded()))%")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(store.brandTint)
                            .contentTransition(.numericText())
                    } else {
                        Text("不可用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let radar = store.radar {
                    Text("雷达额外概率 \(Int(radar.codexProbability.rounded()))% · 数据生成于 \(UsageFormat.timeOfDay(radar.generatedAt))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let error = store.radarError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                } else {
                    Text("等待雷达数据…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .help(radarHelp)
        }
    }

    private var radarHelp: String {
        guard let personal = store.radarPersonal else {
            return "重置雷达：需要本机周额度数据正常且雷达数据在 2 小时内；" + (store.radarError ?? "未获取到数据")
        }
        return "重置雷达：未来 24 小时额度被重置的概率估计（\(personal.reason)）。这是预测不是已发生的事实；已确认的重置历史以小程序为准。数据来源：重置雷达会员 API"
    }

    private var creditsBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
            Text("\(store.snapshot.resetCredits.count) 张重置券可用")
                .font(.caption.weight(.medium))
            Spacer()
            if store.isConsuming {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("立即使用") { store.armCredit() }
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(store.brandTint.opacity(0.20)))
                    .buttonStyle(.plain)
                    .help("消耗一张重置券，立即重置 5 小时与每周额度")
            }
        }
        .foregroundStyle(store.brandTint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(store.brandTint.opacity(0.14)))
        .help("重置券：OpenAI 不定期发放的额度重置券，消耗一张可立即把 5 小时与每周额度同时清零重来")
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: store.errorMessage == nil ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(store.errorMessage == nil ? Color.secondary : Color.red)
            Text(store.errorMessage.map { "刷新失败：\($0)" }
                 ?? "更新于 \(UsageFormat.timeOfDay(store.snapshot.fetchedAt))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(store.refreshLabel)
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .help("上次从 codex 拉取额度数据的时间；可在设置里调整自动刷新间隔。数据仅本机读取，不上传。")
    }
}

struct RingGauge: View {
    let percent: Double
    let tint: Color

    private var fraction: CGFloat { CGFloat(min(max(percent, 0), 100) / 100) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(fraction, 0.001))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint, tint.opacity(0.85)],
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.45), radius: 6)
                .animation(.spring(duration: 0.9, bounce: 0.25), value: fraction)
            VStack(spacing: 0) {
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("已用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LimitRow: View {
    let label: String
    let window: LimitWindow
    let now: Date

    private var tint: Color { UsagePalette.tint(for: window.usedPercent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline)
                Spacer(minLength: 4)
                Text("已用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(UsageFormat.countdown(to: window.resetsAt, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 74, alignment: .trailing)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, proxy.size.width * CGFloat(window.usedPercent / 100)))
                        .animation(.spring(duration: 0.9, bounce: 0.25), value: window.usedPercent)
                }
            }
            .frame(height: 6)
        }
        .help("\(label)：已用 \(Int(window.usedPercent.rounded()))%，剩余 \(100 - Int(window.usedPercent.rounded()))%；\(UsageFormat.countdown(to: window.resetsAt, now: now)) 后重置（\(UsageFormat.absolute(window.resetsAt))）。ChatGPT 客户端里的百分比是「剩余」，两者相加恒为 100%")
    }
}
