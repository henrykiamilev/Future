import Foundation

protocol APIClientProtocol: Sendable {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
    func requestVoid(_ endpoint: APIEndpoint) async throws
    func upload(data: Data, toPresignedURL url: URL, contentType: String) async throws
}

final class APIClient: APIClientProtocol, Sendable {

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: TokenProvider
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, session: URLSession = .shared, tokenProvider: TokenProvider) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    // MARK: - Public

    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let (data, _) = try await execute(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(underlying: error.localizedDescription)
        }
    }

    func requestVoid(_ endpoint: APIEndpoint) async throws {
        let _ = try await execute(endpoint)
    }

    func upload(data: Data, toPresignedURL url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.serverError(statusCode: code, message: "Image upload failed")
        }
    }

    // MARK: - Internal

    private func execute(_ endpoint: APIEndpoint) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try buildRequest(endpoint)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.networkFailure(underlying: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown(statusCode: 0)
        }

        if (200...299).contains(http.statusCode) {
            return (data, http)
        }

        throw mapError(statusCode: http.statusCode, data: data)
    }

    private func buildRequest(_ endpoint: APIEndpoint) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true) else {
            throw APIError.invalidURL
        }

        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = tokenProvider.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func mapError(statusCode: Int, data: Data) -> APIError {
        let decoded = try? decoder.decode(APIErrorResponse.self, from: data)
        let errorCode = decoded?.error ?? ""

        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 429:
            return .rateLimited(retryAfter: nil)
        case 400...499:
            return mapDomainError(errorCode, message: decoded?.message)
        default:
            return .serverError(statusCode: statusCode, message: decoded?.message)
        }
    }

    private func mapDomainError(_ code: String, message: String?) -> APIError {
        switch code {
        case "posting_rate_limit":  return .postingRateLimit(nextAllowedAt: message ?? "")
        case "signature_limit":     return .signatureLimit
        case "tag_limit":           return .tagLimit
        case "already_liked":       return .alreadyLiked
        case "self_like":           return .selfLike
        case "post_expired":        return .postExpired
        case "image_too_large":     return .imageTooLarge
        case "image_dimensions":    return .imageDimensionsExceeded
        case "user_banned":         return .userBanned
        default:                    return .serverError(statusCode: 400, message: message)
        }
    }
}

// MARK: - Token Provider

protocol TokenProvider: Sendable {
    var currentToken: String? { get }
}

final class KeychainTokenProvider: TokenProvider, Sendable {
    private let keychainKey = "auth_token"

    var currentToken: String? {
        // In production: read from Keychain via SecItemCopyMatching.
        // Placeholder for integration with Cognito / Supabase Auth.
        UserDefaults.standard.string(forKey: keychainKey)
    }

    func store(token: String) {
        UserDefaults.standard.set(token, forKey: keychainKey)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: keychainKey)
    }
}
