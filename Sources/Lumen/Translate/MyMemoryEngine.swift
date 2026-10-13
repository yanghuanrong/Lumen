import Foundation

/// MyMemory引擎（免密钥公开接口）。
/// 擅长整句/整段双向翻译，作为有道失败或长文本时的兜底。
/// 免费额度按 IP 限制（约 5000 词/天），足够个人使用。
struct MyMemoryEngine: TranslationEngine {

    let id = "mymemory"
    let displayName = "MyMemory"
    let requiresKey = false
    var strength: EngineStrength { .sentence }

    /// 可选的邮箱参数可提升免费额度
    var contactEmail: String?

    func translate(_ text: String, from: Language, to: Language) async throws -> TranslationOutput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError(message: "输入为空") }

        // MyMemory 单次请求有长度限制（约 500 字节），超长需分块
        let chunks = Self.chunk(trimmed, maxBytes: 480)

        var translatedParts: [String] = []
        for chunk in chunks {
            let part = try await translateChunk(chunk, from: from, to: to)
            translatedParts.append(part)
        }

        var output = TranslationOutput()
        output.engineName = displayName
        output.detected = from
        output.translated = translatedParts.joined(separator: "\n")

        guard !output.translated.isEmpty else {
            throw EngineError(message: "MyMemory 未返回译文")
        }
        return output
    }

    private func translateChunk(_ text: String, from: Language, to: Language) async throws -> String {
        let targetCode = to == .chinese ? "zh-CN" : "en"
        let langPair = from.code + "|" + targetCode

        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")!
        var items = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: langPair),
            URLQueryItem(name: "mt", value: "1")
        ]
        if let email = contactEmail, !email.isEmpty {
            items.append(URLQueryItem(name: "de", value: email))
        }
        comps.queryItems = items

        guard let url = comps.url else { throw EngineError(message: "URL 构造失败") }
        let json = try await HTTPClient.getJSON(url: url)

        guard let root = json as? [String: Any] else {
            throw EngineError(message: "MyMemory 返回格式异常")
        }
        // 额度耗尽时 responseStatus 是 403 之类的数字
        if let status = root["responseStatus"] as? Int, status != 200 {
            let detail = root["responseDetails"] as? String ?? "额度或频率受限"
            throw EngineError(message: "MyMemory: \(detail)")
        }
        guard let data = root["responseData"] as? [String: Any],
              let translated = data["translatedText"] as? String,
              !translated.isEmpty else {
            throw EngineError(message: "MyMemory 未返回译文")
        }
        return decodeEntities(translated)
    }

    // MARK: - 工具

    /// MyMemory 返回 HTML 实体
    private func decodeEntities(_ s: String) -> String {
        var out = s
        let map = [
            "&quot;": "\"", "&apos;": "'", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&#39;": "'", "&nbsp;": " "
        ]
        for (entity, char) in map {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 按句子边界切分，避免破坏 UTF-8
    private static func chunk(_ text: String, maxBytes: Int) -> [String] {
        if text.utf8.count <= maxBytes { return [text] }

        let separators = CharacterSet(charactersIn: "。！？.!?\n")
        var chunks: [String] = []
        var current = ""

        for ch in text {
            current.append(ch)
            let atBoundary = ch.unicodeScalars.first.map { separators.contains($0) } ?? false
            if atBoundary && current.utf8.count >= maxBytes / 2 {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else if current.utf8.count >= maxBytes {
                //超长无标点文本，硬切在字符边界
                chunks.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return chunks.filter { !$0.isEmpty }
    }
}