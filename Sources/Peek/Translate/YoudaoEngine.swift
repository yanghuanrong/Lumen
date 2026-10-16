import Foundation

/// 有道词典 Web 接口引擎。
/// 特点：免密钥、国内直连、同时提供译文 + 音标 + 多词性释义 + 例句 + 词形变化。
/// 注意：这是网页端公开接口，用于个人工具场景，不保证 SLA。
struct YoudaoEngine: TranslationEngine {

    let id = "youdao"
    let displayName = "有道词典"
    let requiresKey = false
    var strength: EngineStrength { .dictionary }

    func translate(_ text: String, from: Language, to: Language) async throws -> TranslationOutput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError(message: "输入为空") }

        let isWord = LanguageDetector.looksLikeSingleWord(trimmed)

        // 有道对"单词"和"句子"用不同 client，返回结构不同
        let client = isWord ? "le" : "dict"
        var comps = URLComponents(string: "https://dict.youdao.com/jsonapi")!
        comps.queryItems = [
            URLQueryItem(name: "jsonversion", value: "2"),
            URLQueryItem(name: "client", value: client),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = comps.url else { throw EngineError(message: "URL 构造失败") }

        let json = try await HTTPClient.getJSON(url: url, headers: [
            "Referer": "https://dict.youdao.com/",
            "Accept": "application/json"
        ])

        guard let root = json as? [String: Any] else {
            throw EngineError(message: "有道返回格式异常")
        }

        var output = TranslationOutput()
        output.engineName = displayName
        output.detected = from

        // --- 1. 音标 ---
        output.phonetics = parsePhonetics(root)

        // --- 2. 译文 ---
        if let translated = parseTranslation(root, fallbackQuery: trimmed) {
            output.translated = translated
        }

        // --- 3. 词典释义 ---
        output.entries = parseEntries(root)

        // --- 4. 词形变化 ---
        output.forms = parseForms(root)

        // --- 5. 例句 ---
        output.examples = parseExamples(root)

        guard output.hasContent else {
            throw EngineError(message: "有道未返回可用结果")
        }
        return output
    }

    // MARK: - 音标

    private func parsePhonetics(_ root: [String: Any]) -> [String] {
        var result: [String] = []

        // 优先词典条目里的音标
        if let words = (root["ec"] as? [String: Any])?["word"] as? [[String: Any]] {
            for entry in words {
                if let uk = entry["ukphone"] as? String, !uk.isEmpty { result.append(uk) }
                if let us = entry["usphone"] as? String, !us.isEmpty { result.append(us) }
            }
        }
        // simple 节点（英译中时有 ukphone/usphone）
        if result.isEmpty, let simple = root["simple"] as? [String: Any] {
            for entry in (simple["word"] as? [[String: Any]] ?? []) {
                if let uk = entry["ukphone"] as? String, !uk.isEmpty { result.append(uk) }
                if let us = entry["usphone"] as? String, !us.isEmpty { result.append(us) }
            }
        }

        // 去重保序
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    // MARK: - 译文

    private func parseTranslation(_ root: [String: Any], fallbackQuery: String) -> String? {
        // 整句翻译走 fanyi 节点
        if let fanyi = root["fanyi"] as? [String: Any] {
            let src = (fanyi["src"] as? String) ?? ""
            if !src.isEmpty { return cleanHTML(src) }
        }

        // web_trans 里的首条候选
        if let webTrans = root["web_trans"] as? [String: Any],
           let list = webTrans["web-translation"] as? [[String: Any]] {
            for item in list {
                guard let trans = item["trans"] as? [[String: Any]] else { continue }
                for t in trans {
                    if let value = t["value"] as? String, !value.isEmpty {
                        return cleanHTML(value)
                    }
                }
            }
        }

        // 中文单词的"return-phrase"兜底
        if let simple = root["simple"] as? [String: Any],
           let words = simple["word"] as? [[String: Any]] {
            for entry in words {
                if let phrase = entry["return-phrase"] as? String,
                   !phrase.isEmpty,
                   phrase != fallbackQuery {
                    return phrase
                }
            }
        }
        return nil
    }

    // MARK: - 释义

    private func parseEntries(_ root: [String: Any]) -> [DictEntry] {
        guard let words = (root["ec"] as? [String: Any])?["word"] as? [[String: Any]] else {
            return []
        }

        var result: [DictEntry] = []
        for word in words {
            guard let trs = word["trs"] as? [[String: Any]] else { continue }
            for group in trs {
                guard let trList = group["tr"] as? [[String: Any]] else { continue }
                for tr in trList {
                    guard let lines = (tr["l"] as? [String: Any])?["i"] as? [String] else { continue }
                    for line in lines {
                        guard let entry = parseEntryLine(line) else { continue }
                        result.append(entry)
                        // 最多保留 6 条，避免面板过长
                        if result.count >= 6 { return result }
                    }
                }
            }
        }
        return result
    }

    /// 有道把词性和释义拼在一行，形如 "n. 招呼，问候"，需要拆开
    private func parseEntryLine(_ line: String) -> DictEntry? {
        let cleaned = cleanHTML(line).trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }

        let knownPOS = [
            "n.", "v.", "vt.", "vi.", "adj.", "adv.", "prep.", "conj.", "pron.",
            "num.", "art.", "int.", "interj.", "aux.", "modal", "pref.", "suf.",
            "abbr.", "det.", "u.", "c.", "pl.", "sing.", "link v.", "phr."
        ]

        for pos in knownPOS.sorted(by: { $0.count > $1.count }) {
            if cleaned.lowercased().hasPrefix(pos) {
                let body = String(cleaned.dropFirst(pos.count))
                    .trimmingCharacters(in: .whitespaces)
                let (definition, example) = splitExample(body)
                return DictEntry(partOfSpeech: pos, definition: definition, example: example)
            }
        }
        return DictEntry(partOfSpeech: nil, definition: cleaned, example: nil)
    }

    /// 有道释义里例句可能以 "例：" 开头，或以引号包裹的英文句子结尾
    private func splitExample(_ body: String) -> (String, String?) {
        for marker in ["例：", "e.g. ", "eg. "] {
            if let range = body.range(of: marker) {
                let def = String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                var ex = String(body[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                ex = ex.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”''"))
                return (def, ex.isEmpty ? nil : ex)
            }
        }
        return (body, nil)
    }

    // MARK: - 词形变化

    private func parseForms(_ root: [String: Any]) -> [String] {
        guard let words = (root["ec"] as? [String: Any])?["word"] as? [[String: Any]] else {
            return []
        }
        var forms: [String] = []
        for word in words {
            for wf in (word["wfs"] as? [[String: Any]] ?? []) {
                guard let inner = wf["wf"] as? [String: Any],
                      let name = inner["name"] as? String,
                      let value = inner["value"] as? String else { continue }
                let text = "\(name): \(value)"
                if !forms.contains(text) { forms.append(text) }
            }
        }
        return Array(forms.prefix(4))
    }

    // MARK: - 例句

    private func parseExamples(_ root: [String: Any]) -> [BilingualExample] {
        var result: [BilingualExample] = []

        // blng_sents_part: 词组/例句对照
        if let part = root["blng_sents_part"] as? [String: Any],
           let pairs = part["sentence-pair"] as? [[String: Any]] {
            for pair in pairs {
                guard let sentence = pair["sentence-eng"] as? String ?? pair["sentence"] as? String,
                      let translation = pair["sentence-translation"] as? String else { continue }
                result.append(BilingualExample(
                    source: cleanHTML(sentence),
                    target: cleanHTML(translation)
                ))
                if result.count >= 4 { return result }
            }
        }

        // auth_sents_part: 例句
        if let auth = root["auth_sents_part"] as? [String: Any],
           let pairs = auth["sents"] as? [[String: Any]] {
            for pair in pairs {
                guard let sentence = pair["s"] as? String,
                      let translation = pair["s_trans"] as? String else { continue }
                result.append(BilingualExample(
                    source: cleanHTML(sentence),
                    target: cleanHTML(translation)
                ))
                if result.count >= 4 { break }
            }
        }
        return result
    }

    // MARK: - 工具

    private func cleanHTML(_ s: String) -> String {
        var out = s
        // 有道在 web_trans 里会插 <b> 标签
        out = out.replacingOccurrences(of: "<b>", with: "")
        out = out.replacingOccurrences(of: "</b>", with: "")
        out = out.replacingOccurrences(of: "<br/>", with: " ")
        out = out.replacingOccurrences(of: "<br>", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}