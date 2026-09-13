import SwiftUI
import AppKit
import Combine
import QuartzCore

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

/// 透明动画层：让卡片以图层动画被菜单栏的圆角形状接住并收口。
private final class SuctionAnimationPanel: NSPanel {
    let animationView: SuctionAnimationView

    init(overlayFrame: NSRect, image: NSImage, sourceFrame: NSRect, targetFrame: NSRect) {
        animationView = SuctionAnimationView(
            frame: NSRect(origin: .zero, size: overlayFrame.size),
            image: image,
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            overlayFrame: overlayFrame
        )
        super.init(contentRect: overlayFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        ignoresMouseEvents = true
        contentView = animationView
    }
}

private final class AnimationCompletionDelegate: NSObject, CAAnimationDelegate {
    private let onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        onFinished()
    }
}

/// 图层化动画保留内容比例，并通过圆角裁切模拟灵动岛的接住与收口。
private final class SuctionAnimationView: NSView {
    private let image: NSImage
    private let sourceFrame: NSRect
    private let targetFrame: NSRect
    private let overlayFrame: NSRect
    private let snapshotLayer = CALayer()
    private var animationCompletion: AnimationCompletionDelegate?
    private var completionHandler: (() -> Void)?

    init(frame: NSRect, image: NSImage, sourceFrame: NSRect, targetFrame: NSRect, overlayFrame: NSRect) {
        self.image = image
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.overlayFrame = overlayFrame
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { nil }

    func start(completion: @escaping () -> Void) {
        guard animationCompletion == nil, let hostLayer = layer else { return }
        completionHandler = completion

        let source = localFrame(sourceFrame)
        let target = localFrame(targetFrame)
        let receiving = localFrame(MinimizeAnimationGeometry.receivingFrame(around: targetFrame))
        let sourceCenter = CGPoint(x: source.midX, y: source.midY)
        let targetCenter = CGPoint(x: target.midX, y: target.midY)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        snapshotLayer.frame = source
        snapshotLayer.contents = snapshotCGImage()
        snapshotLayer.contentsGravity = .resizeAspectFill
        snapshotLayer.contentsScale = scale
        snapshotLayer.cornerRadius = 28
        snapshotLayer.masksToBounds = true
        hostLayer.addSublayer(snapshotLayer)
        CATransaction.commit()

        let duration: CFTimeInterval = 0.54
        let pathAnimation = CAKeyframeAnimation(keyPath: "position")
        let path = CGMutablePath()
        path.move(to: sourceCenter)
        let delta = CGPoint(x: target.midX - source.midX, y: target.midY - source.midY)
        path.addCurve(
            to: targetCenter,
            control1: CGPoint(x: source.midX + delta.x * 0.22, y: source.midY + delta.y * 0.08),
            control2: CGPoint(x: target.midX - delta.x * 0.18, y: target.midY - delta.y * 0.36)
        )
        pathAnimation.path = path
        pathAnimation.calculationMode = .cubicPaced

        let boundsAnimation = CAKeyframeAnimation(keyPath: "bounds.size")
        boundsAnimation.values = [
            NSValue(size: source.size),
            NSValue(size: NSSize(width: source.width * 0.76, height: source.height * 0.76)),
            NSValue(size: receiving.size),
            NSValue(size: NSSize(width: target.width * 1.18, height: target.height * 1.18)),
            NSValue(size: target.size),
        ]
        boundsAnimation.keyTimes = [0, 0.45, 0.77, 0.90, 1]

        let cornerAnimation = CAKeyframeAnimation(keyPath: "cornerRadius")
        cornerAnimation.values = [28, 28, receiving.height / 2, target.height / 2, target.height / 2]
        cornerAnimation.keyTimes = [0, 0.45, 0.77, 0.90, 1]

        let snapshotGroup = CAAnimationGroup()
        snapshotGroup.animations = [pathAnimation, boundsAnimation, cornerAnimation]
        snapshotGroup.duration = duration
        snapshotGroup.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.84, 0.20, 1)
        snapshotGroup.fillMode = .forwards
        snapshotGroup.isRemovedOnCompletion = false
        let delegate = AnimationCompletionDelegate { [weak self] in self?.finish() }
        animationCompletion = delegate
        snapshotGroup.delegate = delegate

        snapshotLayer.add(snapshotGroup, forKey: "suction")
    }

    private func localFrame(_ frame: NSRect) -> CGRect {
        frame.offsetBy(dx: -overlayFrame.minX, dy: -overlayFrame.minY)
    }

    private func snapshotCGImage() -> CGImage? {
        guard let data = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: data)
        else { return nil }
        return representation.cgImage
    }

    private func finish() {
        completionHandler?()
        completionHandler = nil
        animationCompletion = nil
    }
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
    private var minimizeAnimationPanel: NSPanel?
    private var isMinimizing = false
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
        guard !isMinimizing else { return }
        store.collapsed = false
        guard let panel,
              panel.isVisible,
              let menuBarItemFrame = menuBarItemFrameOnScreen(),
              let image = snapshot(of: panel)
        else {
            panel?.orderOut(nil)
            return
        }

        isMinimizing = true
        let targetFrame = MinimizeAnimationGeometry.targetFrame(in: menuBarItemFrame)
        let overlayFrame = MinimizeAnimationGeometry.animationOverlayFrame(from: panel.frame, to: targetFrame)
        let snapshotPanel = SuctionAnimationPanel(overlayFrame: overlayFrame,
                                                  image: image,
                                                  sourceFrame: panel.frame,
                                                  targetFrame: targetFrame)
        minimizeAnimationPanel = snapshotPanel
        snapshotPanel.orderFrontRegardless()
        panel.orderOut(nil)
        snapshotPanel.animationView.start { [weak self, weak snapshotPanel] in
            Task { @MainActor [weak self, weak snapshotPanel] in
                snapshotPanel?.orderOut(nil)
                self?.minimizeAnimationPanel = nil
                self?.isMinimizing = false
            }
        }
    }

    /// 截取当前卡片，避免窗口缩小时触发布局重排，从而得到连续的缩放效果。
    private func snapshot(of panel: NSPanel) -> NSImage? {
        guard let contentView = panel.contentView,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
        else { return nil }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        let image = NSImage(size: contentView.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// 将自绘菜单栏视图的本地坐标转换为屏幕坐标，作为动画的真实终点。
    private func menuBarItemFrameOnScreen() -> NSRect? {
        guard let statusView, let menuBarWindow = statusView.window else { return nil }
        let windowFrame = statusView.convert(statusView.bounds, to: nil)
        return menuBarWindow.convertToScreen(windowFrame)
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
        // 左键直接切换卡片；再次点击即隐藏到菜单栏。
        statusView.onPrimaryAction = { [weak self] in self?.toggleClicked() }
        statusView.onSecondaryAction = { [weak self, weak statusView] in
            guard let self, let statusView else { return }
            self.showStatusMenu(in: statusView)
        }
        guard let button = item.button else {
            CardLog.write("菜单栏按钮创建失败")
            return
        }
        statusView.frame = button.bounds
        statusView.autoresizingMask = [.width, .height]
        button.addSubview(statusView)
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
