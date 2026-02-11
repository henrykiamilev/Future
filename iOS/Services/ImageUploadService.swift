import Foundation
import UIKit

// ============================================================================
// IMAGE UPLOAD SERVICE — SUPABASE STORAGE
// ============================================================================
//
// Pipeline:  UIImage → compress → upload to Supabase Storage → return URL
//
// Supabase Storage flow:
//   1. Compress image (HEIC preferred, JPEG fallback)
//   2. Upload directly to /storage/v1/object/{bucket}/{path}
//      with Bearer token (no presign step needed)
//   3. Public URL: /storage/v1/object/public/{bucket}/{path}
//
// Features:
//   - Compression runs off the main thread
//   - Direct upload to Supabase Storage (no presign round-trip)
//   - URLSession upload task with delegate-based progress tracking
//   - Retry with exponential backoff on transient failures
//   - Cooperative cancellation via Task.isCancelled
//
// ============================================================================

// MARK: - Protocol

protocol ImageUploadServiceProtocol: Sendable {
    func upload(image: UIImage, onProgress: @Sendable @escaping (Double) -> Void) async throws -> UploadedImage
}

// MARK: - Result Type

struct UploadedImage: Sendable {
    let url: String          // CDN-accessible public URL
    let width: Int           // pixel width after compression
    let height: Int          // pixel height after compression
    let sizeBytes: Int       // compressed file size
    let format: CompressedImage.ImageFormat
}

// MARK: - Upload Error

enum UploadError: LocalizedError {
    case compressionFailed(underlying: String)
    case uploadFailed(statusCode: Int, attempt: Int)
    case uploadFailedAllRetries
    case cancelled

    var errorDescription: String? {
        switch self {
        case .compressionFailed(let e):       return "Image compression failed: \(e)"
        case .uploadFailed(let code, let n):  return "Upload failed (HTTP \(code), attempt \(n))."
        case .uploadFailedAllRetries:         return "Upload failed after multiple attempts. Check your connection."
        case .cancelled:                      return "Upload was cancelled."
        }
    }
}

// MARK: - Service Implementation

final class ImageUploadService: ImageUploadServiceProtocol, Sendable {

    private let baseURL: URL         // Supabase project URL
    private let anonKey: String      // Supabase anon key for apikey header
    private let tokenProvider: TokenProvider
    private let compressor: ImageCompressorProtocol
    private let bucket: String
    private let maxRetries = 3
    private let baseRetryDelay: UInt64 = 1_000_000_000  // 1 second

    init(
        baseURL: URL,
        anonKey: String,
        tokenProvider: TokenProvider,
        compressor: ImageCompressorProtocol = ImageCompressor(),
        bucket: String = "post-images"
    ) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.tokenProvider = tokenProvider
        self.compressor = compressor
        self.bucket = bucket
    }

    /// Full pipeline: compress → upload to Supabase Storage → return public URL.
    ///
    /// Progress callback reports 0.0–1.0 across the full pipeline:
    ///   - 0.0–0.2: compression
    ///   - 0.2–0.9: Supabase Storage upload
    ///   - 0.9–1.0: finalization
    func upload(
        image: UIImage,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> UploadedImage {
        try Task.checkCancellation()

        // ──────────────────────────────────────────────
        // Phase 1: Compress (off main thread)
        // ──────────────────────────────────────────────
        onProgress(0.05)

        let compressed: CompressedImage
        do {
            compressed = try await Task.detached(priority: .userInitiated) { [compressor] in
                try compressor.compress(image: image)
            }.value
        } catch {
            throw UploadError.compressionFailed(underlying: error.localizedDescription)
        }

        onProgress(0.20)
        try Task.checkCancellation()

        // ──────────────────────────────────────────────
        // Phase 2: Upload directly to Supabase Storage
        // ──────────────────────────────────────────────
        // Generate a unique file path: {user_id_prefix}/{uuid}.{ext}
        let ext = compressed.format == .heic ? "heic" : "jpg"
        let fileName = "\(UUID().uuidString).\(ext)"
        let storagePath = "/storage/v1/object/\(bucket)/\(fileName)"
        let uploadURL = baseURL.appendingPathComponent(storagePath)

        try await uploadWithRetry(
            data: compressed.data,
            to: uploadURL,
            contentType: compressed.contentType,
            onProgress: { fraction in
                // Map 0.0–1.0 upload progress into 0.2–0.9 overall
                onProgress(0.20 + fraction * 0.70)
            }
        )

        onProgress(0.95)
        try Task.checkCancellation()

        // Construct public URL
        let publicURL = baseURL
            .appendingPathComponent("/storage/v1/object/public/\(bucket)/\(fileName)")
            .absoluteString

        onProgress(1.0)

        return UploadedImage(
            url: publicURL,
            width: compressed.width,
            height: compressed.height,
            sizeBytes: compressed.sizeBytes,
            format: compressed.format
        )
    }

    // MARK: - Upload with Retry & Progress

    private func uploadWithRetry(
        data: Data,
        to url: URL,
        contentType: String,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        var lastError: Error?

        for attempt in 1...maxRetries {
            try Task.checkCancellation()

            do {
                try await performUpload(
                    data: data,
                    to: url,
                    contentType: contentType,
                    onProgress: onProgress
                )
                return // success
            } catch let error as UploadError {
                lastError = error
                if case .uploadFailed = error, attempt < maxRetries {
                    let delay = baseRetryDelay * UInt64(1 << (attempt - 1)) // 1s, 2s, 4s
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw error
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let delay = baseRetryDelay * UInt64(1 << (attempt - 1))
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
            }
        }

        throw lastError ?? UploadError.uploadFailedAllRetries
    }

    private func performUpload(
        data: Data,
        to url: URL,
        contentType: String,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        // Supabase Storage requires apikey + Bearer token
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let token = tokenProvider.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.upload(for: request, from: data)
        } catch {
            session.invalidateAndCancel()
            throw error
        }

        session.invalidateAndCancel()

        guard let http = response as? HTTPURLResponse else {
            throw UploadError.uploadFailed(statusCode: 0, attempt: 1)
        }

        guard (200...299).contains(http.statusCode) else {
            throw UploadError.uploadFailed(statusCode: http.statusCode, attempt: 1)
        }
    }
}

// MARK: - Upload Progress Delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {

    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @Sendable @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(min(fraction, 1.0))
    }
}
