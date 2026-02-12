import Foundation
import Security

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
    private let supabaseAnonKey: String

    init(baseURL: URL, session: URLSession = .shared, tokenProvider: TokenProvider, supabaseAnonKey: String) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.supabaseAnonKey = supabaseAnonKey

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

    private let maxRetries = 3

    private func execute(_ endpoint: APIEndpoint) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try buildRequest(endpoint)

        for attempt in 0..<maxRetries {
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

            // On 401, try to refresh the token once then retry
            if http.statusCode == 401, attempt == 0 {
                if await refreshAccessToken() {
                    // Token refreshed — rebuild request with new token and retry
                    let retryRequest = try buildRequest(endpoint)
                    let (retryData, retryResponse) = try await session.data(for: retryRequest)
                    if let retryHTTP = retryResponse as? HTTPURLResponse,
                       (200...299).contains(retryHTTP.statusCode) {
                        return (retryData, retryHTTP)
                    }
                }
                // Refresh failed or retry still 401 — session is expired
                NotificationCenter.default.post(name: .authSessionExpired, object: nil)
                throw APIError.unauthorized
            }

            // Retry on 429 with exponential backoff
            if http.statusCode == 429, attempt < maxRetries - 1 {
                let delay = UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
                continue
            }

            throw mapError(statusCode: http.statusCode, data: data)
        }

        throw APIError.rateLimited(retryAfter: nil)
    }

    /// Attempt to refresh the access token using the stored refresh token.
    private func refreshAccessToken() async -> Bool {
        guard let keychainProvider = tokenProvider as? KeychainTokenProvider,
              let refreshToken = keychainProvider.currentRefreshToken else {
            return false
        }

        struct RefreshRequest: Encodable {
            let refreshToken: String
        }
        struct RefreshResponse: Decodable {
            let accessToken: String
            let refreshToken: String
        }

        let endpoint = APIEndpoint(
            path: "/auth/v1/token",
            method: .POST,
            queryItems: [.init(name: "grant_type", value: "refresh_token")],
            body: RefreshRequest(refreshToken: refreshToken)
        )

        do {
            let request = try buildRequest(endpoint)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return false
            }
            let decoded = try decoder.decode(RefreshResponse.self, from: data)
            keychainProvider.store(token: decoded.accessToken)
            keychainProvider.storeRefreshToken(decoded.refreshToken)
            return true
        } catch {
            return false
        }
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

        // Supabase requires apikey header on all requests
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let token = tokenProvider.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            // Use anon key as bearer when not authenticated
            request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func mapError(statusCode: Int, data: Data) -> APIError {
        let decoded = try? decoder.decode(APIErrorResponse.self, from: data)
        let errorCode = decoded?.bestErrorCode ?? ""
        let message = decoded?.bestMessage

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
            return mapDomainError(errorCode, message: message)
        default:
            return .serverError(statusCode: statusCode, message: message)
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

// MARK: - Auth Notifications

extension Notification.Name {
    static let authSessionExpired = Notification.Name("authSessionExpired")
}

// MARK: - Token Provider

protocol TokenProvider: Sendable {
    var currentToken: String? { get }
}

final class KeychainTokenProvider: TokenProvider, Sendable {
    private let service = "com.curated.app"
    private let account = "auth_token"
    private let refreshAccount = "refresh_token"

    var currentToken: String? {
        readKeychain(account: account)
    }

    var currentRefreshToken: String? {
        readKeychain(account: refreshAccount)
    }

    func store(token: String) {
        writeKeychain(account: account, value: token)
    }

    func storeRefreshToken(_ token: String) {
        writeKeychain(account: refreshAccount, value: token)
    }

    func clear() {
        deleteKeychain(account: account)
        deleteKeychain(account: refreshAccount)
    }

    // MARK: - Keychain Helpers

    private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func writeKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        deleteKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
