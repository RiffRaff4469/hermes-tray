import Foundation

enum APIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case http(Int)
    case tokenMissing

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "Enter an http or https URL with a host, without credentials, query, or fragment."
        case .invalidResponse: return "The server returned an invalid HTTP response."
        case .http(let code): return "HTTP \(code) from Hermes."
        case .tokenMissing: return "The dashboard HTML did not contain a session token."
        }
    }
}

actor APIClient {
    enum Endpoint: String {
        case home = ""
        case status = "api/status"
        case sessions = "api/sessions"
        case systemStats = "api/system/stats"
    }

    let baseURL: URL
    private let session: URLSession
    private let tokenStore = TokenStore()
    private var token: String?
    private var bootstrapTask: Task<String, Error>?

    static func validatedURL(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw APIError.invalidBaseURL }
        components.scheme = scheme
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let url = components.url else { throw APIError.invalidBaseURL }
        return url
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
        self.token = TokenStore().read(for: baseURL.absoluteString)
    }

    func status() async throws -> AgentStatus {
        try await get(.status, authenticated: false)
    }

    func sessions() async throws -> [Session] {
        let response: SessionsResponse = try await get(.sessions, authenticated: true)
        return response.sessions ?? []
    }

    func systemStats() async throws -> SystemStats {
        try await get(.systemStats, authenticated: true)
    }

    private func bootstrap() async throws -> String {
        if let bootstrapTask { return try await bootstrapTask.value }
        let task = Task<String, Error> {
            let data = try await self.request(.home, token: nil)
            let html = String(decoding: data, as: UTF8.self)
            // Match the inline JavaScript assignment, allowing whitespace and either quote style.
            let regex = try NSRegularExpression(
                pattern: #"window\.__HERMES_SESSION_TOKEN__\s*=\s*["']([^"'\r\n]+)["']"#
            )
            guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { throw APIError.tokenMissing }
            return String(html[range])
        }
        bootstrapTask = task
        defer { bootstrapTask = nil }
        let fresh = try await task.value
        token = fresh
        tokenStore.write(fresh, for: baseURL.absoluteString)
        return fresh
    }

    private func get<T: Decodable>(_ endpoint: Endpoint, authenticated: Bool) async throws -> T {
        var bearer: String?
        if authenticated {
            if let token { bearer = token }
            else { bearer = try await bootstrap() }
        }
        let data: Data
        do {
            data = try await request(endpoint, token: bearer)
        } catch APIError.http(401) where authenticated {
            // Another protected request may already have refreshed the rejected token.
            if let token, token != bearer { bearer = token }
            else { bearer = try await bootstrap() }
            data = try await request(endpoint, token: bearer)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func request(_ endpoint: Endpoint, token: String?) async throws -> Data {
        try Task.checkCancellation()
        let url = endpoint == .home ? baseURL : baseURL.appendingPathComponent(endpoint.rawValue)
        var request = URLRequest(url: url)
        request.setValue(endpoint == .home ? "text/html" : "application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw APIError.http(response.statusCode) }
        return data
    }
}
