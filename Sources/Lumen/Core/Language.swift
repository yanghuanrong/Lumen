import Foundation

/// Lumen 只处理中文 ⇄ 英文两种语言，方向自动判定。
enum Language: String, CaseIterable, Codable, Sendable {
    case chinese
    case english

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "英文"
        }
    }

    /// 有道 / Google 使用的语言代码
    var code: String {
        switch self {
        case .chinese: return "zh-CHS"
        case .english: return "en"
        }
    }

    var badge: String {
        switch self {
        case .chinese: return "中"
        case .english: return "EN"
        }
    }

    var counterpart: Language { self == .chinese ? .english : .chinese }
}

/// 轻量语言识别：按字符构成判定中文 / 英文。
enum LanguageDetector {

    /// - Returns: 能识别时返回语言，否则 nil（空串或纯符号）。
    static func detect(_ text: String) -> Language? {
        var han = 0
        var latin = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF,   // CJK 统一表意
                 0x3400...0x4DBF,   // 扩展 A
                 0xF900...0xFAFF,   // 兼容表意
                 0x3005...0x3007,   // 々〆〇
                 0x3040...0x30FF,   // 日文假名（归入中文方向更符合国内用户预期）
                 0xAC00...0xD7AF:   // 韩文
                han += 1
            case 0x41...0x5A, 0x61...0x7A:
                latin += 1
            default:
                break
            }
        }

        if han == 0 && latin == 0 { return nil }
        return han >= latin ? .chinese : .english
    }

    /// 是否像一个"单词"（用于决定要不要走词典模式）
    static func looksLikeSingleWord(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return false }
        // 空格分隔后只有一段，且不含句末标点
        guard trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).count == 1 else { return false }
        let sentenceEnders: Set<Character> = [".", "?", "!", "。", "？", "！", ",", "，", ";", "；", ":", "："]
        return !trimmed.contains(where: { sentenceEnders.contains($0) })
    }
}