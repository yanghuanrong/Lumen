import AppKit
import SwiftUI

/// 可拖动的标题栏区域。
/// SwiftUI 没有内置窗口拖动能力，这里桥接到 AppKit 的 performDrag。
struct WindowDragArea: NSViewRepresentable {

    func makeNSView(context: Context) -> DragAreaView {
        DragAreaView()
    }

    func updateNSView(_ nsView: DragAreaView, context: Context) {}

    final class DragAreaView: NSView {

        override var acceptsFirstResponder: Bool { false }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}