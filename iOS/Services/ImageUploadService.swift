import Foundation
import UIKit

protocol ImageUploadServiceProtocol: Sendable {
    func upload(image: UIImage) async throws -> UploadedImage
}

struct UploadedImage: Sendable {
    let url: String
    let width: Int
    let height: Int
    let sizeBytes: Int
}

final class ImageUploadService: ImageUploadServiceProtocol, Sendable {

    private let client: APIClientProtocol
    private let compressor: ImageCompressorProtocol

    init(client: APIClientProtocol, compressor: ImageCompressorProtocol = ImageCompressor()) {
        self.client = client
        self.compressor = compressor
    }

    func upload(image: UIImage) async throws -> UploadedImage {
        // 1. Compress and resize
        let compressed = try compressor.compress(image: image)

        // 2. Get presigned upload URL
        let presign: PresignResponse = try await client.request(.requestUploadURL)

        // 3. Upload to presigned URL (S3 / Supabase Storage)
        try await client.upload(
            data: compressed.data,
            toPresignedURL: presign.uploadURL,
            contentType: compressed.contentType
        )

        return UploadedImage(
            url: presign.publicURL,
            width: compressed.width,
            height: compressed.height,
            sizeBytes: compressed.data.count
        )
    }
}

private struct PresignResponse: Decodable {
    let uploadURL: URL
    let publicURL: String

    enum CodingKeys: String, CodingKey {
        case uploadURL = "uploadUrl"
        case publicURL = "publicUrl"
    }
}
