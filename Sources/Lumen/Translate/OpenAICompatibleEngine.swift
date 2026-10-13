import Foundation

/// OpenAI 兼容接口引擎。
/// 兼容 OpenAI / DeepSeek / 智谱 / 月之暗面 / 本地 Ollama / one-api 等。
/// 自定义 baseURL 即可接入任意兼容服务。
struct OpenAICompatibleEngine: TranslationEngine {

    var id: String = "openai"
    var displayName: String = "OpenAI 兼容"
    var requiresKey: Bool = true
    var strength: EngineStrength { .sentence }

    var apiKey: String
    var baseURL: String
    var model: String

    func translate(_ text: String, from: Language, to: Language) async throws -> TranslationOutput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError(message: "输入为空") }

        var endpoint = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if endpoint.hasSuffix("/chat/completions") {
            // 用户填了完整路径
        } else {
            if !endpoint.hasSuffix("/v1") && !endpoint.contains("/v1/") {
                endpoint += "/v1"
            }
            endpoint += "/chat/completions"
        }
        guard let url = URL(string: endpoint) else {
            throw EngineError(message: "接口地址无效: \(baseURL)")
        }

        let targetName = to == .chinese ? "简体中文(zh-CN)" : "英文(en)"
        let systemPrompt = """
        你是一个精确的翻译引擎。只输出译文本身，不要添加解释、音标、引号或任何额外说明。
        将输入从\(from.displayName)翻译为\(targetName)，保持原有的段落和标点结构。
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": trimmed]
            ],
            "temperature": 0.2,
            "stream": false
        ]

        var headers = ["Content-Type": "application/json"]
        if !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }

        let json = try await HTTPClient.postJSON(url: url, body: body, headers: headers)

        guard let root = json as? [String: Any] else {
            throw EngineError(message: "\(displayName) 返回格式异常")
        }
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "未知错误"
            throw EngineError(message: "\(displayName): \(message)")
        }
        guard let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw EngineError(message: "\(displayName) 未返回译文")
        }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<think>", with: "")
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var output = TranslationOutput()
        output.engineName = displayName
        output.detected = from
        output.translated = cleaned

        guard !output.translated.isEmpty else {
            throw EngineError(message: "\(displayName) 返回空内容")
        }
        return output
    }
}