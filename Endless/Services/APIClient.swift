import Foundation

// MARK: - API Error

enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case networkError(Error)
    case unauthorized
    case forbidden(String)
    case notFound
    case serverError(Int, String?)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required"
        case .forbidden(let message):
            return message
        case .notFound:
            return "Resource not found"
        case .serverError(let code, let message):
            return message ?? "Server error (\(code))"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - API Client

/// HTTP client for communicating with the backend API.
/// All requests include Firebase ID token for authentication.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Token provider closure - set by AuthService
    var tokenProvider: (() async throws -> String)?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Config.requestTimeout
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Public Methods

    /// Perform GET request
    func get<T: Decodable>(
        _ endpoint: String,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        let request = try await buildRequest(
            endpoint: endpoint,
            method: "GET",
            queryParams: queryParams,
            timeout: timeout
        )
        return try await perform(request)
    }

    /// Perform POST request with body
    func post<T: Decodable, B: Encodable>(
        _ endpoint: String,
        body: B,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        var request = try await buildRequest(
            endpoint: endpoint,
            method: "POST",
            timeout: timeout
        )
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    /// Perform POST request without expecting response body
    func postVoid<B: Encodable>(
        _ endpoint: String,
        body: B,
        timeout: TimeInterval? = nil
    ) async throws {
        var request = try await buildRequest(
            endpoint: endpoint,
            method: "POST",
            timeout: timeout
        )
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let _: EmptyResponse = try await perform(request)
    }

    /// Perform PUT request with body
    func put<T: Decodable, B: Encodable>(
        _ endpoint: String,
        body: B,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        var request = try await buildRequest(
            endpoint: endpoint,
            method: "PUT",
            timeout: timeout
        )
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    /// Perform DELETE request
    func delete(
        _ endpoint: String,
        timeout: TimeInterval? = nil
    ) async throws {
        let request = try await buildRequest(
            endpoint: endpoint,
            method: "DELETE",
            timeout: timeout
        )
        let _: EmptyResponse = try await perform(request)
    }

    // MARK: - Private Methods

    private func buildRequest(
        endpoint: String,
        method: String,
        queryParams: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> URLRequest {
        var urlString = Config.apiBaseURL + endpoint

        // Add query parameters
        if let queryParams = queryParams, !queryParams.isEmpty {
            var components = URLComponents(string: urlString)
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            urlString = components?.string ?? urlString
        }

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if let timeout = timeout {
            request.timeoutInterval = timeout
        }

        // Add auth token
        if let tokenProvider = tokenProvider {
            let token = try await tokenProvider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        if Config.enableNetworkLogging {
            print("[API] \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        if Config.enableNetworkLogging {
            print("[API] Response: \(httpResponse.statusCode)")
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }

        case 401:
            throw APIError.unauthorized

        case 403:
            let message = try? decoder.decode(ErrorResponse.self, from: data)
            throw APIError.forbidden(message?.detail ?? "Access denied")

        case 404:
            throw APIError.notFound

        case 500...599:
            let message = try? decoder.decode(ErrorResponse.self, from: data)
            throw APIError.serverError(httpResponse.statusCode, message?.detail)

        default:
            throw APIError.serverError(httpResponse.statusCode, nil)
        }
    }
}

// MARK: - Response Types

struct EmptyResponse: Decodable {}

struct ErrorResponse: Decodable {
    let detail: String?
}
