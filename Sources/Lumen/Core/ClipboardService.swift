import AppKit
import Foundation

/// 剪贴板封装。
/// 用enum + static 方法实现单例，避免 struct 初始化的并发隔离问题。
enum ClipboardService {

    @discardableResult
    static func write(_ text: String) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return pb.changeCount
    }

    static func currentText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}