import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 快捷键录制控件：点击后按下组合键即可完成录制。
struct HotKeyRecorder: NSViewRepresentable {

    @Binding var hotKey: HotKey
    var onChanged: (HotKey) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let view = HotKeyRecorderView()
        view.onHotKey = { newKey in
            hotKey = newKey
            onChanged(newKey)
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderView, context: Context) {
        nsView.onHotKey = { newKey in
            hotKey = newKey
            onChanged(newKey)
        }
        nsView.setHotKey(hotKey)
    }

    final class HotKeyRecorderView: NSView {
        var onHotKey: ((HotKey) -> Void)?
        var currentHotKey: HotKey = .default

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 28) }

        private var isRecording = false
        private let label = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .center
            label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            label.textColor = .labelColor
            addSubview(label)

            setHotKey(currentHotKey)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            label.frame = bounds
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if isRecording {
                NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
                let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
                path.fill()
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        func setHotKey(_ key: HotKey) {
            currentHotKey = key
            label.stringValue = key.displayString
        }

        override func mouseDown(with event: NSEvent) {
            isRecording = true
            label.stringValue = "按下组合键…"
            needsDisplay = true
            window?.makeFirstResponder(self)
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            setHotKey(currentHotKey)
            needsDisplay = true
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // ⇧ 不能单独作为修饰键，否则全局打不出大写字母
            guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
                NSSound.beep()
                label.stringValue = "需搭配 ⌘/⌥/⌃（⇧ 不能单独用）"
                return
            }

            let key = HotKey(
                keyCode: event.keyCode,
                carbonModifiers: HotKey.carbonModifiers(from: flags)
            )
            isRecording = false
            setHotKey(key)
            needsDisplay = true
            onHotKey?(key)

            window?.makeFirstResponder(nil)
        }
    }
}