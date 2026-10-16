import Foundation

/// 翻译引擎协议。各引擎实现同一接口，由 Translator 统一调度与降级。
protocol TranslationEngine: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// 是否需要用户配置密钥
    var requiresKey: Bool { get }
    /// 引擎擅长的输入类型，用于自动选择
    var strength: EngineStrength { get }

    func translate(_ text: String, from: Language, to: Language) async throws -> TranslationOutput
}

enum EngineStrength: Int, Sendable {
    /// 擅长整句 / 段落翻译
    case sentence = 0
    /// 擅长单词，含词典释义、音标、例句
    case dictionary = 1
}

/// 引擎错误
struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}