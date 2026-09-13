import AppKit

@main
struct MinimizeAnimationGeometryProbe {
    static func main() {
        let menuBarItem = NSRect(x: 840, y: 1056, width: 62, height: 24)
        let target = MinimizeAnimationGeometry.targetFrame(in: menuBarItem)
        let source = NSRect(x: 360, y: 420, width: 324, height: 384)
        let overlay = MinimizeAnimationGeometry.animationOverlayFrame(from: source, to: target)
        let receivingFrame = MinimizeAnimationGeometry.receivingFrame(around: target)

        guard menuBarItem.contains(target),
              abs(target.midX - menuBarItem.midX) < 0.001,
              abs(target.midY - menuBarItem.midY) < 0.001,
              target.width < menuBarItem.width,
              target.height < menuBarItem.height
        else {
            fatalError("FAIL: 吸入动画的终点没有位于菜单栏用量图标中央。")
        }

        guard overlay.contains(source), overlay.contains(target) else {
            fatalError("FAIL: 吸入动画层没有覆盖从卡片到菜单栏的完整路径。")
        }

        guard receivingFrame.contains(target),
              receivingFrame.width > target.width,
              receivingFrame.height > target.height,
              abs(receivingFrame.midX - target.midX) < 0.001,
              abs(receivingFrame.midY - target.midY) < 0.001
        else {
            fatalError("FAIL: 接住内容的胶囊范围没有完整包围菜单栏终点。")
        }

        print("PASS: 吸入动画终点居中，动画层覆盖完整路径，胶囊会先接住内容。")
    }
}
