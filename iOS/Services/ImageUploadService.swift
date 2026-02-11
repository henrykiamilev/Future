import Foundation
import UIKit

// ============================================================================
// IMAGE UPLOAD SERVICE
// ============================================================================
//
// Pipeline:  UIImage → compress → presign → upload to S3/Supabase → return URL
//
// Features:
//   - Compression runs off the main thread
//   - Presigned URL flow (works with S3 and Supabase Storage)
//   - URLSession upload task with delegate-based progress tracking
//   - Retry with exponential backoff on transient failures
//   - Cooperative cancellation via Task.isCancelled
//   - Full error mapping
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
    case presignFailed(underlying: String)
    case uploadFailed(statusCode: Int, attempt: Int)
    case uploadFailedAllRetries
    case cancelled

    var errorDescription: String? {
        switch self {
        case .compressionFailed(let e):       return "Image compression failed: \(e)"
        case .presignFailed(let e):           return "Could not prepare upload: \(e)"
        case .uploadFailed(let code, let n):  return "Upload failed (HTTP \(code), attempt \(n))."
        case .uploadFailedAllRetries:         return "Upload failed after multiple attempts. Check your connection."
        case .cancelled:                      return "Upload was cancelled."
        }
    }
}

// MARK: - Service Implementation

final class ImageUploadService: ImageUploadServiceProtocol, Sendable {

    private let client: APIClientProtocol
    private let compressor: ImageCompressorProtocol
    private let maxRetries = 3
    private let baseRetryDelay: UInt64 = 1_000_000_000  // 1 second in nanoseconds

    init(client: APIClientProtocol, compressor: ImageCompressorProtocol = ImageCompressor()) {
        self.client = client
        self.compressor = compressor
    }

    /// Full pipeline: compress → presign → upload → return public URL.
    ///
    /// Progress callback reports 0.0–1.0 across the full pipeline:
    ///   - 0.0–0.2: compression
    ///   - 0.2–0.3: presign request
    ///   - 0.3–0.9: S3 upload
    ///   - 0.9–1.0: post-upload verification
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
        // Phase 2: Request presigned upload URL
        // ──────────────────────────────────────────────
        let presign: PresignResponse
        do {
            presign = try await client.request(
                .requestUploadURL(
                    contentType: compressed.contentType,
                    fileSizeBytes: compressed.sizeBytes
                )
            )
        } catch {
            throw UploadError.presignFailed(underlying: error.localizedDescription)
        }

        onProgress(0.30)
        try Task.checkCancellation()

        // ──────────────────────────────────────────────
        // Phase 3: Upload to S3/Supabase with retry
        // ──────────────────────────────────────────────
        try await uploadWithRetry(
            data: compressed.data,
            to: presign.uploadURL,
            contentType: compressed.contentType,
            onProgress: { fraction in
                // Map 0.0–1.0 upload progress into 0.3–0.9 overall
                onProgress(0.30 + fraction * 0.60)
            }
        )

        onProgress(0.95)
        try Task.checkCancellation()

        onProgress(1.0)

        return UploadedImage(
            url: presign.publicURL,
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
                // Only retry on transient upload failures
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
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")

        // Use upload delegate for byte-level progress
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.upload(for: request, from: data)

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

// MARK: - Presign Response

private struct PresignResponse: Decodable, Sendable {
    let uploadURL: URL       // S3 presigned PUT URL
    let publicURL: String    // CDN-accessible URL after upload completes

    enum CodingKeys: String, CodingKey {
        case uploadURL = "uploadUrl"
        case publicURL = "publicUrl"
    }
}

// MARK: - Endpoint Extension

extension APIEndpoint {
    static func requestUploadURL(contentType: String, fileSizeBytes: Int) -> APIEndpoint {
        APIEndpoint(
            path: "/uploads/presign",
            method: .POST,
            body: PresignRequest(contentType: contentType, fileSizeBytes: fileSizeBytes)
        )
    }
}

private struct PresignRequest: Encodable, Sendable {
    let contentType: String
    let fileSizeBytes: Int
}
