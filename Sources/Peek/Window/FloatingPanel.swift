import AppKit
import SwiftUI

/// 悬浮面板窗口。
/// 关键点：
/// 1. `isFloatingPanel` + `level = .floating`，始终在普通窗口之上
/// 2. 关闭按钮隐藏（Esc 代替），避免误触导致窗口消失
/// 3. 无标题栏样式，用自定义顶部条拖动窗口
/// 4. `hidesOnDeactivate = false`，切到别的 App 时面板仍在
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        // 让面板可以接收键盘输入而不抢走前台App 的焦点
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // 自定义阴影/圆角由 SwiftUI 层负责
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // 透明无阴影的原生阴影会与SwiftUI 圆角冲突
        hasShadow = false
    }

    /// NSPanel 需要显式允许成为 key，否则面板内输入框无法获得焦点
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 面板控制器：负责窗口生命周期与显隐位置计算。
@MainActor
final class FloatingPanelController {

    private(set) var panel: FloatingPanel!
    private let settings: SettingsStore

    /// 默认尺寸
    private let defaultSize = NSSize(width: 460, height: 340)
    private let minSize = NSSize(width: 360, height: 240)

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// 注入 SwiftUI 内容
    func setContentView<Content: View>(_ view: Content) {
        // 使用忽略 intrinsic size 的 hosting，避免 loading↔结果切换时窗口被撑缩抖动
        let hosting = FixedSizeHostingView(rootView: AnyView(view))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func show() {
        positionWindow()
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: false)
    }

    func hide() {
        panel.orderOut(nil)
        panel.resignKey()
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - 位置

    private func positionWindow() {
        var frame = panel.frame
        frame.size = clampedSize(frame.size)

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            // 鼠标点作为窗口左上角（macOS 坐标系 y 向上），面板出现在鼠标右下方
            frame.origin.x = mouse.x
            frame.origin.y = mouse.y - frame.height

            // 逐边夹紧，保证窗口完整落在屏幕可见区域内
            if frame.maxX > visible.maxX {
                frame.origin.x = visible.maxX - frame.width
            }
            if frame.minX < visible.minX {
                frame.origin.x = visible.minX
            }
            if frame.maxY > visible.maxY {
                frame.origin.y = visible.maxY - frame.height
            }
            if frame.minY < visible.minY {
                frame.origin.y = visible.minY
            }
            // 鼠标紧贴屏幕边缘且窗口高于可见区域时，右下都无法完全容纳，优先保证底部可见
            if frame.height > visible.height {
                frame.origin.y = visible.minY
            }
        } else {
            // 无鼠标位置信息时退回主屏居中
            frame.origin = NSPoint(
                x: (NSScreen.main?.visibleFrame.midX ?? 0) - frame.width / 2,
                y: (NSScreen.main?.visibleFrame.midY ?? 0) - frame.height / 2
            )
        }

        panel.setFrame(frame, display: false)
    }

    private func clampedSize(_ size: NSSize) -> NSSize {
        NSSize(
            width: max(minSize.width, min(size.width, 900)),
            height: max(minSize.height, min(size.height, 700))
        )
    }

    // MARK: - 初始化

    func buildPanel() {
        panel = FloatingPanel(contentRect: NSRect(
            origin: .zero, size: clampedSize(defaultSize)
        ))
        panel.minSize = minSize
        panel.setContentSize(clampedSize(defaultSize))
        panel.isReleasedWhenClosed = false
    }
}

/// 不向 NSPanel 上报 intrinsicContentSize，窗口尺寸只由用户/定位逻辑控制。
private final class FixedSizeHostingView: NSHostingView<AnyView> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}