import Foundation

/// 轻量 HTTP 客户端：统一 UA、超时、重试与错误信息。
/// 不引入任何第三方依赖。
struct HTTPClient {

    struct HTTPError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    static let defaultUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

    static func send(
        _ request: URLRequest,
        timeout: TimeInterval = 15,
        retries: Int = 2,
        decode: Bool = true
    ) async throws -> Data {
        var lastError: Error = HTTPError(status: -1, message: "未知错误")

        for attempt in 0...retries {
            do {
                var req = request
                req.timeoutInterval = timeout
                if req.value(forHTTPHeaderField: "User-Agent") == nil {
                    req.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
                }

                let (data, response) = try await URLSession.shared.data(for: req)

                guard let http = response as? HTTPURLResponse else {
                    throw HTTPError(status: -1, message: "响应格式异常")
                }
                guard (200..<300).contains(http.statusCode) else {
                    // 4xx 基本是参数错误，重试无意义
                    if http.statusCode >= 400 && http.statusCode < 500 {
                        let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
                        throw HTTPError(status: http.statusCode,
                                        message: "HTTP \(http.statusCode)\(preview.isEmpty ? "" : " · \(preview)")")
                    }
                    throw HTTPError(status: http.statusCode, message: "HTTP \(http.statusCode)")
                }
                return data
            } catch {
                lastError = error
                if let httpErr = error as? HTTPError, (400..<500).contains(httpErr.status) { throw httpErr }
                if attempt < retries {
                    try? await Task.sleep(nanoseconds: UInt64(350_000_000 * (attempt + 1)))
                }
            }
        }
        throw lastError
    }

    static func getJSON(url: URL, headers: [String: String] = [:]) async throws -> Any {
        var req = URLRequest(url: url)
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let data = try await send(req)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func postJSON(url: URL, body: [String: Any], headers: [String: String] = [:]) async throws -> Any {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(req)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}