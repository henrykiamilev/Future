import UIKit

protocol ImageCompressorProtocol: Sendable {
    func compress(image: UIImage) throws -> CompressedImage
}

struct CompressedImage: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let contentType: String
}

final class ImageCompressor: ImageCompressorProtocol, Sendable {

    // PRD constraints:
    // - 2048px max long edge
    // - Target 500KB–1.5MB
    // - Hard cap 2.5MB
    // - HEIC preferred, JPEG fallback

    private let maxDimension: CGFloat = 2048
    private let targetMaxBytes = 1_500_000   // 1.5 MB target
    private let hardCapBytes = 2_621_440     // 2.5 MB hard cap

    func compress(image: UIImage) throws -> CompressedImage {
        // 1. Resize if needed
        let resized = resize(image: image, maxDimension: maxDimension)

        let width = Int(resized.size.width * resized.scale)
        let height = Int(resized.size.height * resized.scale)

        // 2. Try HEIC first
        if let heicData = heicData(for: resized) {
            if heicData.count <= hardCapBytes {
                return CompressedImage(
                    data: heicData,
                    width: width,
                    height: height,
                    contentType: "image/heic"
                )
            }
        }

        // 3. Fallback to JPEG with progressive quality reduction
        let qualities: [CGFloat] = [0.85, 0.75, 0.65, 0.50]
        for quality in qualities {
            if let jpegData = resized.jpegData(compressionQuality: quality),
               jpegData.count <= hardCapBytes {
                return CompressedImage(
                    data: jpegData,
                    width: width,
                    height: height,
                    contentType: "image/jpeg"
                )
            }
        }

        // 4. Last resort: heavy compression
        guard let finalData = resized.jpegData(compressionQuality: 0.3) else {
            throw CompressionError.failed
        }

        guard finalData.count <= hardCapBytes else {
            throw CompressionError.tooLarge
        }

        return CompressedImage(
            data: finalData,
            width: width,
            height: height,
            contentType: "image/jpeg"
        )
    }

    // MARK: - Resize

    private func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)

        guard longestEdge > maxDimension else { return image }

        let scale = maxDimension / longestEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - HEIC Encoding

    private func heicData(for image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.heic" as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.80
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
    }
}

enum CompressionError: LocalizedError {
    case failed
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .failed: return "Image compression failed."
        case .tooLarge: return "Image is too large even after compression."
        }
    }
}
