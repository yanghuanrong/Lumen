import AppKit
import Combine
import SwiftUI

/// 面板的视图模型，串起「呼出 → 粘贴 → 翻译 → 复制」主流程。
@MainActor
final class TranslationViewModel: ObservableObject {

    @Published var inputText: String = ""
    @Published var copiedFlash: Bool = false
    @Published private(set) var lastAction: Action?

    enum Action: Equatable {
        case copied
        case autoCopied
    }

    private let translator: Translator
    private let settings: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    /// 呼出时的剪贴板快照，用于避免污染用户剪贴板
    private var clipboardSnapshot: ClipboardService.Snapshot?

    var output: TranslationOutput? { translator.output }
    var isTranslating: Bool { translator.isTranslating }
    var errorMessage: String? { translator.errorMessage }

    init(translator: Translator, settings: SettingsStore) {
        self.translator = translator
        self.settings = settings
        // 面板只观察 viewModel；翻译状态在 translator 上，必须转发否则 UI 会卡在「翻译中…」
        translator.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - 呼出

    /// 热键触发：读取剪贴板 → 填充输入框 → 自动翻译
    func onHotkeyTriggered() {
        snapshotClipboard()
        loadClipboardIfNeeded()
        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translator.translate(inputText)
        }
    }

    /// 演示模式：直接填入文本并翻译，不读剪贴板
    func demoTranslate(_ text: String) {
        inputText = text
        translator.translate(text)
    }

    private func snapshotClipboard() {
        clipboardSnapshot = ClipboardService.snapshot()
    }

    private func loadClipboardIfNeeded() {
        guard settings.autoPasteClipboard else {
            if !settings.keepLastInput {
                inputText = ""
            }
            return
        }

        guard let text = ClipboardService.currentText(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !settings.keepLastInput { inputText = "" }
            return
        }

        // 命中断板哨兵值说明没有新内容
        if text == LumenStrings.monitorSentinel {
            if !settings.keepLastInput { inputText = "" }
            return
        }

        // 避免重复翻译同样的内容
        if text != inputText {
            inputText = text
        } else if settings.keepLastInput {
            return
        }
    }

    // MARK: - 翻译

    func translate() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            translator.clear()
            return
        }
        translator.translate(inputText)
    }

    /// 监听输出变化，必要时自动复制
    func startObserving() {
        translator.$output
            .receive(on: RunLoop.main)
            .sink { [weak self] output in
                guard let self, let output, output.hasContent else { return }
                if self.settings.autoCopyResult {
                    self.copyResult(output)
                    self.lastAction = .autoCopied
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 复制

    /// 复制译文到剪贴板，并按设置决定是否还原用户原剪贴板
    func copyResult(_ output: TranslationOutput? = nil) {
        guard let text = (output ?? translator.output)?.translated,
              !text.isEmpty else { return }

        // 若译文与输入完全一致（如单词音标查询），不写剪贴板避免污染
        guard text != inputText else {
            flashCopied()
            return
        }

        ClipboardService.write(text)
        flashCopied()
        lastAction = .copied
    }

    /// 关闭面板时按需还原剪贴板
    func onHide() {
        if settings.autoCopyResult, let out = translator.output, !out.translated.isEmpty {
            if let snapshot = clipboardSnapshot {
                _ = ClipboardService.restoreIfUnchanged(snapshot, newText: out.translated)
            }
        }
        translator.cancel()
    }

    func clear() {
        inputText = ""
        translator.clear()
        clipboardSnapshot = nil
    }

    private func flashCopied() {
        copiedFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            copiedFlash = false
        }
    }

    /// 当前输入对应的方向描述，如"英 → 中"
    var directionText: String {
        guard let detected = LanguageDetector.detect(inputText) else { return "自动识别" }
        return "\(detected.badge) → \(detected.counterpart.badge)"
    }

    /// 输入是否是单词（决定UI 是否突出显示词典信息）
    var isWordInput: Bool {
        LanguageDetector.looksLikeSingleWord(inputText)
    }
}