import AppKit
import Foundation

// 纯AppKit 入口：Lumen 以 LSUIElement 方式运行（无 Dock 图标），
// 窗口全部由 NSPanel 手动管理，因此不使用 SwiftUI 的 App 生命周期。

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)

    // 自检模式：swift run Lumen --selftest
    if CommandLine.arguments.contains("--selftest") {
        Task {
            await SelfTest.run()
            exit(0)
        }
        NSApplication.shared.run()
        return
    }

    // 离屏渲染模式：把面板渲染成 PNG，用于无人工干预时验证 UI
    // 用法：./Lumen --render "serendipity" /tmp/out.png
    if let renderIndex = CommandLine.arguments.firstIndex(of: "--render") {
        let text = CommandLine.arguments.count > renderIndex + 1
            ? CommandLine.arguments[renderIndex + 1] : "serendipity"
        let path = CommandLine.arguments.count > renderIndex + 2
            ? CommandLine.arguments[renderIndex + 2] : "/tmp/lumen-panel.png"

        Task {
            let ok = await PanelRenderer.render(text: text, to: path)
            print(ok ? "✅ 已渲染到 \(path)" : "❌ 渲染失败")
            exit(ok ? 0 : 1)
        }
        NSApplication.shared.run()
        return
    }

    // 渲染设置页：./Lumen --render-settings /tmp/out.png
    if CommandLine.arguments.contains("--render-settings") {
        let path = "/tmp/lumen-settings.png"
        Task { @MainActor in
            let ok = SettingsRenderer.render(to: path)
            print(ok ? "✅ 已渲染到 \(path)" : "❌ 渲染失败")
            exit(ok ? 0 : 1)
        }
        NSApplication.shared.run()
        return
    }

    // 演示模式：启动即呼出面板并填入示例单词，方便验证 UI 与翻译链路
    // 用法：./Lumen --demo "serendipity"
    if let demoIndex = CommandLine.arguments.firstIndex(of: "--demo") {
        let demoText = CommandLine.arguments.count > demoIndex + 1
            ? CommandLine.arguments[demoIndex + 1]
            : "serendipity"

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            delegate.demoShow(text: demoText)
        }
    }

    // DEBUG 构建下自动呼出面板，省去每次手动按快捷键。
    // 想保持安静调试可设环境变量 LUMEN_NO_AUTO_SHOW=1。
    #if DEBUG
    if !CommandLine.arguments.contains("--no-auto-show"),
       ProcessInfo.processInfo.environment["LUMEN_NO_AUTO_SHOW"] == nil {
        let demoText = ProcessInfo.processInfo.environment["LUMEN_DEMO_TEXT"] ?? "serendipity"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            delegate.demoShow(text: demoText)
        }
    }
    #endif

    NSApplication.shared.run()
}