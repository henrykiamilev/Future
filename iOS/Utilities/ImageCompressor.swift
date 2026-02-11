import UIKit
import ImageIO
import UniformTypeIdentifiers

// ============================================================================
// IMAGE COMPRESSION PIPELINE
// ============================================================================
//
// PRD constraints enforced here:
//   - Max 2048px long edge
//   - Target 500KB–1.5MB
//   - Hard cap 2.5MB
//   - HEIC preferred, JPEG fallback
//   - EXIF location data stripped
//
// Memory safety:
//   - All heavy work runs inside autoreleasepool to prevent transient spikes
//   - CGImage-level operations (no UIImage round-trips during encoding)
//   - Binary search for quality level instead of linear scan
//
// ============================================================================

// MARK: - Protocol

protocol ImageCompressorProtocol: Sendable {
    func compress(image: UIImage) throws -> CompressedImage
}

// MARK: - Output

struct CompressedImage: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let sizeBytes: Int
    let contentType: String      // "image/heic" or "image/jpeg"
    let format: ImageFormat

    enum ImageFormat: String, Sendable {
        case heic, jpeg
    }
}

// MARK: - Error

enum CompressionError: LocalizedError {
    case cgImageCreationFailed
    case encodingFailed(format: String)
    case exceedsHardCap(bytes: Int)
    case imageIsEmpty

    var errorDescription: String? {
        switch self {
        case .cgImageCreationFailed:
            return "Failed to create image for processing."
        case .encodingFailed(let format):
            return "Image encoding failed (\(format))."
        case .exceedsHardCap(let bytes):
            return "Image is \(bytes / 1024)KB — exceeds 2.5MB limit even after maximum compression."
        case .imageIsEmpty:
            return "Captured image has no data."
        }
    }
}

// MARK: - Compressor

final class ImageCompressor: ImageCompressorProtocol, Sendable {

    // PRD constants
    private let maxLongEdge: CGFloat = 2048
    private let targetMinBytes = 500_000       // 500 KB — below this we're over-compressing
    private let targetMaxBytes = 1_500_000     // 1.5 MB — ideal upper bound
    private let hardCapBytes   = 2_621_440     // 2.5 MB — absolute server limit

    // Binary search bounds for quality
    private let qualityMin: CGFloat = 0.10
    private let qualityMax: CGFloat = 0.95
    private let qualitySteps = 6               // binary search iterations

    func compress(image: UIImage) throws -> CompressedImage {
        guard image.size.width > 0, image.size.height > 0 else {
            throw CompressionError.imageIsEmpty
        }

        // ────────────────────────────────────────────────
        // Step 1: Resize (if needed) inside autoreleasepool
        // ────────────────────────────────────────────────
        let resizedCGImage: CGImage = try autoreleasepool {
            let resized = resizeIfNeeded(image)
            guard let cg = resized.cgImage else {
                throw CompressionError.cgImageCreationFailed
            }
            return cg
        }

        let pixelWidth = resizedCGImage.width
        let pixelHeight = resizedCGImage.height

        // ────────────────────────────────────────────────
        // Step 2: Try HEIC encoding
        // ────────────────────────────────────────────────
        if let heicResult = try? encodeHEIC(cgImage: resizedCGImage, width: pixelWidth, height: pixelHeight) {
            return heicResult
        }

        // ────────────────────────────────────────────────
        // Step 3: Fall back to JPEG with binary-searched quality
        // ────────────────────────────────────────────────
        return try encodeJPEG(cgImage: resizedCGImage, width: pixelWidth, height: pixelHeight)
    }

    // MARK: - Resize

    private func resizeIfNeeded(_ image: UIImage) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)

        guard longEdge > maxLongEdge else { return image }

        let scale = maxLongEdge / longEdge
        let newSize = CGSize(
            width: (size.width * scale).rounded(.down),
            height: (size.height * scale).rounded(.down)
        )

        // UIGraphicsImageRenderer handles autorelease internally
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0             // exact pixel dimensions, no @2x/@3x
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - HEIC Encoding

    private func encodeHEIC(cgImage: CGImage, width: Int, height: Int) throws -> CompressedImage {
        // Binary search for best quality that fits under hardCap
        // Start at 0.80 — HEIC is very efficient so this usually fits
        let qualities: [CGFloat] = [0.80, 0.65, 0.50, 0.35]

        for quality in qualities {
            if let data = autoreleasepool(invoking: {
                encodeWithCGImageDestination(
                    cgImage: cgImage,
                    utType: UTType.heic.identifier as CFString,
                    quality: quality
                )
            }) {
                if data.count <= hardCapBytes {
                    return CompressedImage(
                        data: data,
                        width: width,
                        height: height,
                        sizeBytes: data.count,
                        contentType: "image/heic",
                        format: .heic
                    )
                }
            }
        }

        throw CompressionError.encodingFailed(format: "HEIC")
    }

    // MARK: - JPEG Encoding (binary search)

    private func encodeJPEG(cgImage: CGImage, width: Int, height: Int) throws -> CompressedImage {
        // Binary search: find the highest quality where size <= hardCap,
        // ideally landing in the 500KB–1.5MB target range.

        var lo = qualityMin
        var hi = qualityMax
        var bestData: Data?
        var bestQuality: CGFloat = lo

        for _ in 0..<qualitySteps {
            let mid = (lo + hi) / 2.0
            let data: Data? = autoreleasepool {
                guard let cg = UIImage(cgImage: cgImage).jpegData(compressionQuality: mid) else {
                    return nil
                }
                return cg
            }

            guard let encoded = data else {
                hi = mid
                continue
            }

            if encoded.count <= hardCapBytes {
                bestData = encoded
                bestQuality = mid

                if encoded.count < targetMinBytes {
                    // Under-compressed — increase quality
                    lo = mid
                } else if encoded.count > targetMaxBytes {
                    // Over target — decrease quality
                    hi = mid
                } else {
                    // In the sweet spot — done
                    break
                }
            } else {
                // Over hard cap — decrease quality
                hi = mid
            }
        }

        // If binary search didn't find anything under hard cap, try minimum quality
        if bestData == nil || bestData!.count > hardCapBytes {
            bestData = autoreleasepool {
                UIImage(cgImage: cgImage).jpegData(compressionQuality: qualityMin)
            }
        }

        guard let finalData = bestData else {
            throw CompressionError.encodingFailed(format: "JPEG")
        }

        guard finalData.count <= hardCapBytes else {
            throw CompressionError.exceedsHardCap(bytes: finalData.count)
        }

        return CompressedImage(
            data: finalData,
            width: width,
            height: height,
            sizeBytes: finalData.count,
            contentType: "image/jpeg",
            format: .jpeg
        )
    }

    // MARK: - CGImageDestination Encoding (HEIC)
    // Uses ImageIO directly for HEIC — this also strips EXIF location data.

    private func encodeWithCGImageDestination(
        cgImage: CGImage,
        utType: CFString,
        quality: CGFloat
    ) -> Data? {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            utType,
            1,
            nil
        ) else { return nil }

        // Properties: set quality, strip GPS/location metadata
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyGPSDictionary: NSNull(),           // strip GPS
            kCGImagePropertyExifDictionary: [                  // strip sensitive EXIF
                kCGImagePropertyExifUserComment: NSNull()
            ] as [CFString: Any]
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
    }
}
