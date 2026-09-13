import AppKit

/// 计算卡片被吸入原生菜单栏项目时的最终位置。
/// 终点始终位于真实菜单栏项目中央，以适配用户调整过的菜单栏排列。
enum MinimizeAnimationGeometry {
    static func targetFrame(in menuBarItemFrame: NSRect) -> NSRect {
        let size = NSSize(
            width: min(28, max(18, menuBarItemFrame.width * 0.45)),
            height: min(18, max(14, menuBarItemFrame.height * 0.75))
        )
        return NSRect(
            x: menuBarItemFrame.midX - size.width / 2,
            y: menuBarItemFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 动画层覆盖起点、终点及周围缓冲，保证吸入轨迹不会被裁切。
    static func animationOverlayFrame(from sourceFrame: NSRect, to targetFrame: NSRect) -> NSRect {
        sourceFrame.union(targetFrame).insetBy(dx: -36, dy: -36)
    }

    /// 在菜单栏图标附近先接住内容、再收口的圆角胶囊。
    static func receivingFrame(around targetFrame: NSRect) -> NSRect {
        let size = NSSize(width: max(52, targetFrame.width + 20),
                          height: max(24, targetFrame.height + 4))
        return NSRect(x: targetFrame.midX - size.width / 2,
                      y: targetFrame.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }
}
