import Foundation

/// App configuration for backend URLs and feature flags.
enum Config {
    // MARK: - Backend

    /// Backend API base URL
    /// Change this to your deployed backend URL in production
    #if DEBUG
    static let backendURL = "http://localhost:8000"
    #else
    static let backendURL = "https://api.endless.app"
    #endif

    /// API version prefix
    static let apiPrefix = "/api"

    /// Full API base URL
    static var apiBaseURL: String {
        backendURL + apiPrefix
    }

    // MARK: - Timeouts

    /// Default request timeout in seconds
    static let requestTimeout: TimeInterval = 30

    /// AI generation timeout (longer due to Gemini processing)
    static let aiGenerationTimeout: TimeInterval = 120

    // MARK: - Feature Flags

    /// Enable debug logging for network requests
    static let enableNetworkLogging = true
}
