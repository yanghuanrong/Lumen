import AppKit
import SwiftUI

/// 离屏渲染验证：把面板视图渲染成 PNG。
/// 不依赖窗口位置与屏幕录制权限，用于在无人工干预时确认 UI 真的能画出来。
/// 用法： ./Peek --render "serendipity" /tmp/out.png
@MainActor
enum PanelRenderer {

    static func render(text: String, to path: String) async -> Bool {
        let settings = SettingsStore()
        let translator = Translator(settings: settings)
        let viewModel = TranslationViewModel(translator: translator, settings: settings)

        viewModel.demoTranslate(text)

        // 等待翻译完成（最多 20 秒）
        for _ in 0..<200 {
            if !translator.isTranslating { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let view = TranslationPanelView(
            viewModel: viewModel,
            settings: settings,
            onClose: {},
            onOpenSettings: {},
            onHideRequest: {}
        )
        .frame(width: 460, height: 340)
        .background(Color(nsColor: .windowBackgroundColor))

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 340)
        hosting.layoutSubtreeIfNeeded()

        // 渲染为位图
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write(Data("渲染失败：无法创建位图\n".utf8))
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("渲染失败：无法编码 PNG\n".utf8))
            return false
        }

        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            FileHandle.standardError.write(Data("写入失败：\(error)\n".utf8))
            return false
        }
    }
}
/// 渲染设置窗口，用于验证设置界面。
@MainActor
enum SettingsRenderer {
    static func render(to path: String) -> Bool {
        let settings = SettingsStore()
        let view = SettingsView(settings: settings, onHotKeyChanged: { _ in }, onClose: {})
            .frame(width: 460, height: 560)

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 560)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        try? png.write(to: URL(fileURLWithPath: path))
        return true
    }
}
