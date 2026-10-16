import Foundation

/// 一条词典释义
struct DictEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    /// 词性，如 "n." / "v." / "adj."
    var partOfSpeech: String?
    /// 释义正文
    var definition: String
    /// 例句
    var example: String?
}

/// 双语例句
struct BilingualExample: Identifiable, Hashable, Sendable {
    let id = UUID()
    var source: String
    var target: String
}

/// 一次翻译的完整结果
struct TranslationOutput: Sendable {
    /// 主译文（整段文本）
    var translated: String = ""
    /// 词典释义（单词模式下有值）
    var entries: [DictEntry] = []
    /// 音标，如 "həˈloʊ"
    var phonetics: [String] = []
    /// 双语例句
    var examples: [BilingualExample] = []
    /// 引擎名，用于状态栏展示
    var engineName: String = ""
    /// 检测到的源语言
    var detected: Language?
    /// 词形变化，如复数/时态
    var forms: [String] = []

    var hasContent: Bool {
        !translated.isEmpty || !entries.isEmpty
    }

    /// 音标展示。
    /// 有道有时返回 "/həˈloʊ/"，有时直接返回 "ˌserənˈdɪpəti"（无包裹符号），
    /// 因此不能只认斜杠括号开头，只要非空即可展示。
    var phoneticDisplay: String? {
        phonetics.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 按词性分组的释义，便于 UI 分段渲染
    var groupedEntries: [PartOfSpeechGroup] {
        var order: [String] = []
        var buckets: [String: [DictEntry]] = [:]
        for entry in entries {
            let key = entry.partOfSpeech ?? ""
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.map { key in
            PartOfSpeechGroup(
                id: key,
                partOfSpeech: key.isEmpty ? nil : key,
                definitions: buckets[key] ?? []
            )
        }
    }
}

/// 同一词性下的多条释义
struct PartOfSpeechGroup: Identifiable, Hashable, Sendable {
    var id: String
    var partOfSpeech: String?
    var definitions: [DictEntry]
}