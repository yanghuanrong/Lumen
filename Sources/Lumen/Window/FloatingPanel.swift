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
    private var windowObserver: NSObjectProtocol?

    /// 记录上一次位置，避免每次都居中导致闪烁
    private var lastFrame: NSRect?

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

        if let lastFrame, isFrameOnScreen(lastFrame) {
            frame = lastFrame
        } else {
            // 默认贴到当前鼠标所在屏幕的右上角，符合划词工具习惯
            if let screen = screenUnderMouse() {
                let visible = screen.visibleFrame
                frame.size = clampedSize(defaultSize)
                frame.origin.x = visible.maxX - frame.width - 24
                frame.origin.y = visible.maxY - frame.height - 24
            } else {
                frame.size = clampedSize(defaultSize)
                // 无鼠标位置信息时退回主屏居中
                frame.origin = NSPoint(
                    x: (NSScreen.main?.visibleFrame.midX ?? 0) - frame.width / 2,
                    y: (NSScreen.main?.visibleFrame.midY ?? 0) - frame.height / 2
                )
            }
        }

        frame.size = clampedSize(frame.size)
        panel.setFrame(frame, display: false)
        lastFrame = frame
    }

    private func clampedSize(_ size: NSSize) -> NSSize {
        NSSize(
            width: max(minSize.width, min(size.width, 900)),
            height: max(minSize.height, min(size.height, 700))
        )
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private func isFrameOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    // MARK: - 初始化

    func buildPanel() {
        panel = FloatingPanel(contentRect: NSRect(
            origin: .zero, size: clampedSize(defaultSize)
        ))
        panel.minSize = minSize
        panel.setContentSize(clampedSize(defaultSize))
        panel.isReleasedWhenClosed = false

        // 拖动后记住位置
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastFrame = self?.panel.frame
            }
        }
    }

    deinit {
        if let windowObserver {
            NotificationCenter.default.removeObserver(windowObserver)
        }
    }
}

/// 不向 NSPanel 上报 intrinsicContentSize，窗口尺寸只由用户/定位逻辑控制。
private final class FixedSizeHostingView: NSHostingView<AnyView> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}