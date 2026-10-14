import Foundation

/// 谷歌翻译引擎（免密钥公开接口）。
/// 使用 translate.googleapis.com 的 gtx 端点，整句翻译质量高。
/// 注意：非官方接口，国内网络环境可能需要代理。
struct GoogleEngine: TranslationEngine {

    let id = "google"
    let displayName = "谷歌翻译"
    let requiresKey = false
    var strength: EngineStrength { .sentence }

    func translate(_ text: String, from: Language, to: Language) async throws -> TranslationOutput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError(message: "输入为空") }

        let sl = from == .chinese ? "zh-CN" : "en"
        let tl = to == .chinese ? "zh-CN" : "en"

        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sl),
            URLQueryItem(name: "tl", value: tl),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = comps.url else { throw EngineError(message: "URL 构造失败") }

        let data = try await HTTPClient.send(URLRequest(url: url))
        let json = try JSONSerialization.jsonObject(with: data)

        // 返回结构：[[["译文","原文",null,null,...],...],...]
        guard let sentences = (json as? [Any])?.first as? [[Any]] else {
            throw EngineError(message: "谷歌返回格式异常")
        }

        var translated = ""
        for sentence in sentences {
            if let seg = sentence.first as? String {
                translated += seg
            }
        }
        guard !translated.isEmpty else {
            throw EngineError(message: "谷歌未返回译文")
        }

        var output = TranslationOutput()
        output.engineName = displayName
        output.detected = from
        output.translated = translated
        return output
    }
}
