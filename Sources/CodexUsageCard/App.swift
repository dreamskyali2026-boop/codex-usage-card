import SwiftUI
import AppKit
import Combine

@main
struct CodexUsageCardApp {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--pct"), index + 1 < args.count, let v = Int(args[index + 1]) {
            LaunchOptions.previewPct = v
        }
        if let index = args.firstIndex(of: "--preview"), index + 1 < args.count {
            PreviewRenderer.render(to: args[index + 1])
            return
        }
        if let index = args.firstIndex(of: "--preview-collapsed"), index + 1 < args.count {
            PreviewRenderer.render(to: args[index + 1], collapsed: true)
            return
        }
        if let index = args.firstIndex(of: "--icon"), index + 1 < args.count {
            IconRenderer.render(to: args[index + 1])
            return
        }
        LaunchOptions.openSettings = args.contains("--open-settings")
        LaunchOptions.makeKey = args.contains("--make-key")
        LaunchOptions.testAlert = args.contains("--test-alert")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum LaunchOptions {
    static var openSettings = false
    static var makeKey = false
    static var testAlert = false
    static var previewPct: Int?
}

final class GlassPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 376, height: 420),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DragHostingView<Content: View>: NSHostingView<Content> {
    var onDragDelta: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    private var last: NSPoint?

    override func mouseDown(with event: NSEvent) {
        last = NSEvent.mouseLocation
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        if let last {
            onDragDelta?(NSPoint(x: now.x - last.x, y: now.y - last.y))
        }
        last = now
    }

    override func mouseUp(with event: NSEvent) {
        last = nil
        onDragEnd?()
        super.mouseUp(with: event)
    }
}

/// 菜单栏里的自绘用量标记：圆环表示比例，文字显示已用百分比。
final class UsageMenuBarView: NSView {
    static let width: CGFloat = 62
    static let height: CGFloat = 24

    var onPrimaryAction: (() -> Void)?
    var onSecondaryAction: (() -> Void)?
    private var usedPercent: Double?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Codex 用量"
    }

    required init?(coder: NSCoder) { nil }

    func update(usedPercent: Double?) {
        self.usedPercent = usedPercent
        needsDisplay = true
    }

    /// 顶部菜单栏圆环只承担警示职责，不跟随用户主题色。
    private var alertTint: NSColor {
        NSColor(UsagePalette.alertTint(for: usedPercent))
    }

    override func draw(_ dirtyRect: NSRect) {
        let ringRect = NSRect(x: 5, y: 4, width: 16, height: 16)
        let center = NSPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringRect.width / 2 - 1.4

        let track = NSBezierPath(ovalIn: ringRect.insetBy(dx: 1.4, dy: 1.4))
        track.lineWidth = 2.8
        NSColor.labelColor.withAlphaComponent(0.24).setStroke()
        track.stroke()

        if let usedPercent {
            let fraction = min(max(usedPercent, 0), 100) / 100
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center,
                          radius: radius,
                          startAngle: 90,
                          endAngle: 90 - CGFloat(fraction * 360),
                          clockwise: true)
            arc.lineWidth = 2.8
            arc.lineCapStyle = .round
            alertTint.setStroke()
            arc.stroke()
        } else {
            alertTint.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
        }

        let label = usedPercent.map { "\(Int($0.rounded()))%" } ?? "Codex"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: NSPoint(x: 26, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    override func mouseUp(with event: NSEvent) {
        onPrimaryAction?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryAction?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var panel: GlassPanel?
    private var statusItem: NSStatusItem?
    private var statusView: UsageMenuBarView?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CardLog.write("应用启动")
        store.start()
        setupStatusItem()
        setupPanel()
        bindStatusTitle()
        applyAppearance(store.appearance)
        if LaunchOptions.openSettings { store.showSettings = true }
        store.$collapsed
            .dropFirst()
            .sink { [weak self] _ in self?.syncPanelSize() }
            .store(in: &bag)
        store.$showSettings
            .dropFirst()
            .sink { [weak self] _ in self?.syncPanelSize() }
            .store(in: &bag)
        store.$creditArmed
            .dropFirst()
            .sink { [weak self] _ in self?.syncPanelSize() }
            .store(in: &bag)
        store.$appearance
            .dropFirst()
            .sink { [weak self] mode in self?.applyAppearance(mode) }
            .store(in: &bag)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        if LaunchOptions.testAlert {
            store.$snapshot
                .filter { !$0.isStale }
                .first()
                .sink { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self?.store.fireTestAlert()
                    }
                }
                .store(in: &bag)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let panel, !panel.isVisible {
            let fitted = (panel.contentView as? DragHostingView<CardView>)?.fittingSize ?? panel.frame.size
            place(panel: panel, size: fitted)
            panel.orderFrontRegardless()
        }
        return true
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func setupPanel() {
        let panel = GlassPanel()
        let hosting = DragHostingView(rootView: cardView())
        hosting.onDragDelta = { [weak self] delta in self?.moveWindow(delta: delta) }
        hosting.focusRingType = .none
        panel.contentView = hosting
        let fitted = hosting.fittingSize
        panel.setContentSize(fitted)
        place(panel: panel, size: fitted)
        if LaunchOptions.makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        self.panel = panel
    }

    private func cardView() -> CardView {
        CardView(
            store: store,
            onRefresh: { [weak self] in self?.store.refresh() },
            onToggleCollapse: { [weak self] in self?.minimizeToMenuBar() },
            onClose: { [weak self] in self?.panel?.orderOut(nil) }
        )
    }

    /// 减号代表收起到系统菜单栏；恢复入口始终是顶部的用量图标。
    private func minimizeToMenuBar() {
        store.collapsed = false
        panel?.orderOut(nil)
    }

    private func place(panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let saved = UserDefaults.standard.string(forKey: "panelOrigin") ?? ""
        if !saved.isEmpty {
            let point = NSPointFromString(saved)
            if frame.contains(NSPoint(x: point.x + 40, y: point.y + 40)) {
                panel.setFrameOrigin(point)
                return
            }
        }
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 24,
                                     y: frame.maxY - size.height - 20))
    }

    private func moveWindow(delta: NSPoint) {
        guard let panel else { return }
        var origin = panel.frame.origin
        origin.x += delta.x
        origin.y += delta.y
        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: "panelOrigin")
    }

    private func syncPanelSize() {
        guard let panel, let hosting = panel.contentView as? DragHostingView<CardView> else { return }
        DispatchQueue.main.async {
            hosting.layoutSubtreeIfNeeded()
            let newSize = hosting.fittingSize
            var frame = panel.frame
            let maxX = frame.maxX, maxY = frame.maxY
            frame.size = newSize
            frame.origin = NSPoint(x: maxX - newSize.width, y: maxY - newSize.height)
            panel.setFrame(frame, display: true, animate: true)
            UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: "panelOrigin")
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: UsageMenuBarView.width)
        // 使用固定身份，避免继承系统为旧 Item-0 保存的隐藏/排序状态。
        item.autosaveName = "CodexUsageMenuBar"
        item.isVisible = true
        let statusView = UsageMenuBarView(frame: NSRect(x: 0, y: 0,
                                                        width: UsageMenuBarView.width,
                                                        height: UsageMenuBarView.height))
        statusView.onPrimaryAction = { [weak self, weak statusView] in
            guard let self, let statusView else { return }
            self.showStatusMenu(in: statusView)
        }
        statusView.onSecondaryAction = { [weak self, weak statusView] in
            guard let self, let statusView else { return }
            self.showStatusMenu(in: statusView)
        }
        item.view = statusView
        statusItem = item
        self.statusView = statusView
    }

    private func showStatusMenu(in view: NSView) {
        let popup = NSMenu()
        popup.addItem(toggleItem())
        popup.addItem(NSMenuItem(title: "立即刷新", action: #selector(refreshClicked), keyEquivalent: "r"))
        popup.addItem(.separator())
        popup.addItem(NSMenuItem(title: "退出 Codex 用量", action: #selector(quitClicked), keyEquivalent: "q"))
        for item in popup.items { item.target = self }
        popup.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
    }

    private func toggleItem() -> NSMenuItem {
        let visible = panel?.isVisible ?? false
        return NSMenuItem(title: visible ? "隐藏卡片" : "显示卡片",
                          action: #selector(toggleClicked), keyEquivalent: "")
    }

    @objc private func toggleClicked() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            let fitted = (panel.contentView as? DragHostingView<CardView>)?.fittingSize ?? panel.frame.size
            place(panel: panel, size: fitted)
            panel.orderFrontRegardless()
        }
    }

    @objc private func refreshClicked() { store.refresh() }

    @objc private func quitClicked() { NSApp.terminate(nil) }

    private func bindStatusTitle() {
        Publishers.CombineLatest(store.$snapshot, store.$now)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, now in
                self?.updateStatusItem(snapshot: snapshot, now: now)
            }
            .store(in: &bag)
    }

    private func updateStatusItem(snapshot: UsageSnapshot, now: Date) {
        guard let statusView else { return }
        let primary = snapshot.primary
        let secondary = snapshot.secondary
        let reserve = snapshot.extras.first?.window

        var tip = "Codex 用量"
        if let primary {
            tip += "：5 小时窗口已用 \(Int(primary.usedPercent.rounded()))%，"
                + "\(UsageFormat.countdown(to: primary.resetsAt, now: now)) 后重置"
        }
        if let secondary {
            tip += "；每周已用 \(Int(secondary.usedPercent.rounded()))%"
        }
        if let reserve {
            tip += "；GPT 储备已用 \(Int(reserve.usedPercent.rounded()))%"
        }
        if !snapshot.resetCredits.isEmpty {
            tip += "；\(snapshot.resetCredits.count) 张重置券可用"
        }
        tip += "。左键显示/隐藏卡片，右键出菜单。"
        statusView.update(usedPercent: primary?.usedPercent)
        statusView.toolTip = tip
    }
}

enum PreviewRenderer {
    @MainActor
    static func render(to path: String, collapsed: Bool = false) {
        RenderMode.useGlass = false
        let store = UsageStore()
        store.snapshot = .demo
        if let pct = LaunchOptions.previewPct {
            store.snapshot.primary?.usedPercent = Double(pct)
        }
        store.now = Date()
        store.collapsed = collapsed
        let card = CardView(store: store)
            .padding(48)
            .background(
                LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.30),
                                        Color(red: 0.75, green: 0.25, blue: 0.65),
                                        Color(red: 0.20, green: 0.35, blue: 0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("render failed\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        } catch {
            FileHandle.standardError.write(Data("write failed\n".utf8))
            exit(1)
        }
    }
}

extension UsageSnapshot {
    static var demo: UsageSnapshot {
        let now = Date()
        return UsageSnapshot(
            fetchedAt: now,
            planType: "plus",
            accountId: "demo",
            accountEmail: "demo@example.com",
            primary: LimitWindow(usedPercent: 20, windowDurationMins: 300,
                                 resetsAt: now.addingTimeInterval(1 * 3600 + 35 * 60 + 12)),
            secondary: LimitWindow(usedPercent: 25, windowDurationMins: 10080,
                                   resetsAt: now.addingTimeInterval(3 * 86400 + 19 * 3600)),
            extras: [
                .init(id: "base_model_inference", label: "GPT 储备额度",
                      window: LimitWindow(usedPercent: 76, windowDurationMins: 10080,
                                          resetsAt: now.addingTimeInterval(6 * 86400 + 17 * 3600))),
            ],
            resetCredits: [ResetCredit(id: "demo-credit", title: "Full reset (Weekly + 5 hr)",
                                       status: "available", expiresAt: nil)],
            reachedType: nil
        )
    }
}
