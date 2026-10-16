import AppKit
import Carbon.HIToolbox
import Foundation

/// 命令行自检：验证语言识别与各引擎连通性。
/// 用法： swift run Peek --selftest
enum SelfTest {

    static func run() async {
        print("=== Peek 自检 ===\n")

        // 1. 语言识别
        print("[1] 语言识别")
        let samples = [
            ("hello world", Language.english),
            ("你好世界", .chinese),
            ("serendipity", .english),
            ("翻译", .chinese),
            ("今天天气不错", .chinese),
            ("OpenAI API", .english),
        ]
        for (text, expected) in samples {
            let detected = LanguageDetector.detect(text) ?? .english
            let mark = detected == expected ? "✓" : "✗"
            print("    \(mark) \"\(text)\" -> \(detected.displayName)")
        }

        // 2. 单词识别
        print("\n[2] 单词判定")
        for text in ["hello", "serendipity", "你好", "hello world", "这是，一句话。"] {
            print("    \(LanguageDetector.looksLikeSingleWord(text) ? "单词" : "句子"): \(text)")
        }

        // 2.5 快捷键映射（防止键码表写错）
        print("\n[2.5] 快捷键")
        let keyChecks: [(HotKey, String)] = [
            (HotKey(keyCode: UInt16(kVK_ANSI_D), carbonModifiers: 0), "D"),
            (HotKey(keyCode: UInt16(kVK_ANSI_A), carbonModifiers: 0), "A"),
            (HotKey(keyCode: UInt16(kVK_ANSI_0), carbonModifiers: 0), "0"),
            (HotKey(keyCode: UInt16(kVK_Delete), carbonModifiers: 0), "Delete"),
            (HotKey(keyCode: UInt16(kVK_Escape), carbonModifiers: 0), "Esc")
        ]
        for (key, expected) in keyChecks {
            let actual = HotKey.keyName(key.keyCode)
            print("    \(actual == expected ? "✓" : "✗") \(expected) -> \(actual)")
        }
        print("    默认快捷键: \(HotKey.default.displayString)")

        // 修饰键往返转换，确保 ⌥⌘⇧⌃ 能正确显示与注册
        print("\n[2.6] 修饰键往返")
        let modCases: [(NSEvent.ModifierFlags, String)] = [
            ([.option], "⌥"),
            ([.command], "⌘"),
            ([.command, .shift], "⇧⌘"),
            ([.control, .option], "⌃⌥"),
            ([.command, .option, .shift, .control], "⌃⌥⇧⌘")
        ]
        for (flags, expected) in modCases {
            let carbon = HotKey.carbonModifiers(from: flags)
            let key = HotKey(keyCode: UInt16(kVK_ANSI_D), carbonModifiers: carbon)
            let actual = key.displayString
            // 实际显示顺序是 ⌃⌥⇧⌘ + 字母，比较时只看符号前缀
            let gotPrefix = String(actual.dropLast())
            print("    \(gotPrefix == expected ? "✓" : "✗") \(expected) -> \(actual)")
        }

        // 3. 引擎连通性
        print("\n[3] 引擎连通性")

        let settings = SettingsStore()

        await test(
            name: "有道词典 · 英译中",
            engine: YoudaoEngine(),
            text: "serendipity",
            settings: settings
        )
        await test(
            name: "有道词典 · 中译英",
            engine: YoudaoEngine(),
            text: "你好世界",
            settings: settings
        )
        await test(
            name: "有道词典 · 整句（预期失败：词典引擎不处理长句）",
            engine: YoudaoEngine(),
            text: "今天天气非常好，我们出去散步吧。",
            settings: settings
        )
        await test(
            name: "MyMemory · 英译中",
            engine: MyMemoryEngine(),
            text: "Good morning, have a nice day.",
            settings: settings
        )
        await test(
            name: "MyMemory · 中译英",
            engine: MyMemoryEngine(),
            text: "今天天气非常好。",
            settings: settings
        )

        // 4. 完整调度链路（模拟真实使用：自动模式）
        print("\n[4] 自动调度链路")
        await testAuto(settings: settings, text: "serendipity")
        await testAuto(settings: settings, text: "ephemeral")
        await testAuto(settings: settings, text: "今天天气非常好，我们出去散步吧。")
        await testAuto(settings: settings, text: "The quick brown fox jumps over the lazy dog.")

        print("\n=== 完成 ===")
    }

    /// 走完整 Translator，验证引擎选择与降级
    @MainActor
    private static func testAuto(settings: SettingsStore, text: String) async {
        let translator = Translator(settings: settings)
        let start = Date()
        translator.translate(text)

        // 等待完成
        for _ in 0..<80 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !translator.isTranslating { break }
        }

        let ms = Int(Date().timeIntervalSince(start) * 1000)
        if let error = translator.errorMessage {
            print("    ✗ \"\(text.prefix(24))\" -> \(error)")
        } else if let out = translator.output {
            let route = translator.servedFromCache ? " (缓存)" : ""
            print("    ✓ \"\(text.prefix(24))\" [\(ms)ms]\(route) via \(out.engineName)")
            if !out.translated.isEmpty {
                print("        \(out.translated.prefix(64))")
            }
            if !out.entries.isEmpty {
                print("        释义 \(out.entries.count) 条 · 例句 \(out.examples.count) 条")
            }
        } else {
            print("    ✗ \"\(text.prefix(24))\" 无输出")
        }
    }

    @MainActor
    private static func test(
        name: String,
        engine: any TranslationEngine,
        text: String,
        settings: SettingsStore
    ) async {
        let source = LanguageDetector.detect(text) ?? .english
        let target = source.counterpart
        let start = Date()

        do {
            let result = try await engine.translate(text, from: source, to: target)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            print("    ✓ \(name) [\(ms)ms]")
            if !result.translated.isEmpty {
                print("        译文: \(result.translated.prefix(70))")
            }
            if let phonetic = result.phoneticDisplay {
                print("        音标: \(phonetic)")
            }
            print("        释义: \(result.entries.count) 条, 例句 \(result.examples.count) 条")
        } catch {
            print("    ✗ \(name) -> \(error.localizedDescription)")
        }
    }
}