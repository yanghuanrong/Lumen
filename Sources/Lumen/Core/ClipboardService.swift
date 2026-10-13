import AppKit
import Foundation

/// 剪贴板封装：带内容快照，便于翻译后把用户原来的剪贴板内容还回去。
/// 用enum + static 方法实现单例，避免 struct 初始化的并发隔离问题。
enum ClipboardService {

    struct Snapshot {
        let text: String?
        let changeCount: Int
    }

    @discardableResult
    static func write(_ text: String) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return pb.changeCount
    }

    /// 读取当前文本与变更计数
    static func snapshot() -> Snapshot {
        let pb = NSPasteboard.general
        return Snapshot(text: pb.string(forType: .string), changeCount: pb.changeCount)
    }

    static func currentText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// 若剪贴板内容在翻译期间未被用户改动，则还原为快照内容。
    /// 返回是否发生了还原。
    @discardableResult
    static func restoreIfUnchanged(_ snapshot: Snapshot, newText: String) -> Bool {
        let pb = NSPasteboard.general
        // 用户已经自己改过剪贴板 → 不动
        guard pb.changeCount == snapshot.changeCount else { return false }
        // 我们自己写进去的译文 → 不还原也没意义，但避免重复写
        guard pb.string(forType: .string) == newText else { return false }
        guard let original = snapshot.text else { return false }
        write(original)
        return true
    }

    var isSentinelOnClipboard: Bool {
        NSPasteboard.general.string(forType: .string) == LumenStrings.monitorSentinel
    }
}

enum LumenStrings {
    /// 剪贴板监听的哨兵值，用于识别"空内容"
    static let monitorSentinel = "\u{200B}LUMEN_CLIPBOARD_WATCH\u{200B}"
}