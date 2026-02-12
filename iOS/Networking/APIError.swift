import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: Date?)
    case serverError(statusCode: Int, message: String?)
    case decodingFailed(underlying: String)
    case networkFailure(underlying: String)
    case unknown(statusCode: Int)

    // Domain-specific errors returned by the backend
    case postingRateLimit(nextAllowedAt: String)
    case signatureLimit
    case tagLimit
    case alreadyLiked
    case selfLike
    case postExpired
    case imageTooLarge
    case imageDimensionsExceeded
    case userBanned

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .forbidden:
            return "You don't have permission to do that."
        case .notFound:
            return "The requested content was not found."
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .serverError(_, let message):
            return message ?? "Something went wrong. Please try again."
        case .decodingFailed:
            return "Unexpected response from the server."
        case .networkFailure:
            return "Network connection failed. Check your connection."
        case .unknown:
            return "Something went wrong."
        case .postingRateLimit(let next):
            return "You can post again at \(next)."
        case .signatureLimit:
            return "You already have 3 signature posts. Remove one first."
        case .tagLimit:
            return "Maximum 3 tags per post."
        case .alreadyLiked:
            return "You've already liked this post."
        case .selfLike:
            return "You can't like your own post."
        case .postExpired:
            return "This post has expired."
        case .imageTooLarge:
            return "Image exceeds the 2.5 MB limit."
        case .imageDimensionsExceeded:
            return "Image dimensions exceed 2048px."
        case .userBanned:
            return "Your account has been suspended."
        }
    }
}

struct APIErrorResponse: Decodable {
    // Supabase GoTrue format: {"error": "...", "error_description": "..."}
    let error: String?
    let errorDescription: String?  // decoded from "error_description" via convertFromSnakeCase

    // Supabase GoTrue v2 format: {"error_code": "...", "msg": "..."}
    let errorCode: String?         // decoded from "error_code" via convertFromSnakeCase
    let msg: String?

    // Supabase PostgREST format: {"message": "...", "code": "..."}
    let message: String?

    /// Best available user-facing message across all Supabase error formats.
    var bestMessage: String? {
        errorDescription ?? msg ?? message
    }

    /// Best available error code across all formats.
    var bestErrorCode: String? {
        errorCode ?? error
    }
}
