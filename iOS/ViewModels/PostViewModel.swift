import Foundation
import UIKit
import AVFoundation

// ============================================================================
// POST VIEW MODEL
// ============================================================================
//
// State machine:
//   .needsPermission → .camera → .preview → .tagging → .uploading → .success
//                                   ↑                                    │
//                                   └────────── .error ←─────────────────┘
//
// Wires the full pipeline:
//   CameraCoordinator.capturePhoto()
//   → ImageUploadService.upload(image:onProgress:)
//       → ImageCompressor.compress(image:)        [off main thread]
//       → APIClient presign request               [async]
//       → URLSession upload to S3 with retry      [async, progress tracked]
//   → PostService.createPost()                    [server enforces 24h rule]
//
// ============================================================================

@MainActor
final class PostViewModel: ObservableObject {

    // MARK: - State

    enum PostState: Equatable {
        case needsPermission
        case camera
        case preview
        case tagging
        case uploading(progress: Double)
        case success(nextAllowedAt: Date)
        case error(String)

        static func == (lhs: PostState, rhs: PostState) -> Bool {
            switch (lhs, rhs) {
            case (.needsPermission, .needsPermission): return true
            case (.camera, .camera): return true
            case (.preview, .preview): return true
            case (.tagging, .tagging): return true
            case (.uploading(let a), .uploading(let b)): return a == b
            case (.success(let a), .success(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var state: PostState = .camera
    @Published var capturedImage: UIImage?
    @Published var tags: [TagInput] = []

    // Tag input fields
    @Published var tagLabel: String = ""
    @Published var tagURL: String = ""

    // Camera
    let camera = CameraCoordinator()

    // MARK: - Dependencies

    private let imageUploadService: ImageUploadServiceProtocol
    private let postService: PostServiceProtocol
    private var uploadTask: Task<Void, Never>?

    init(imageUploadService: ImageUploadServiceProtocol, postService: PostServiceProtocol) {
        self.imageUploadService = imageUploadService
        self.postService = postService
    }

    // MARK: - Camera Authorization

    func checkCameraAuthorization() async {
        let granted = await CameraAuthorization.requestAccess()
        if granted {
            state = .camera
            camera.start()
        } else {
            state = .needsPermission
        }
    }

    // MARK: - Capture Flow

    func capturePhoto() {
        Task {
            do {
                let image = try await camera.capturePhoto()
                capturedImage = image
                state = .preview
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func retakePhoto() {
        capturedImage = nil
        tags = []
        tagLabel = ""
        tagURL = ""
        state = .camera
        camera.start()
    }

    func proceedToTagging() {
        state = .tagging
    }

    // MARK: - Tag Management (max 3)

    var canAddTag: Bool {
        tags.count < 3 && !tagLabel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func addTag() {
        guard canAddTag else { return }
        let url = tagURL.trimmingCharacters(in: .whitespaces)
        tags.append(TagInput(
            label: tagLabel.trimmingCharacters(in: .whitespaces),
            externalURL: url.isEmpty ? nil : url
        ))
        tagLabel = ""
        tagURL = ""
    }

    func removeTag(at index: Int) {
        guard tags.indices.contains(index) else { return }
        tags.remove(at: index)
    }

    // MARK: - Full Upload Pipeline

    func submitPost() {
        guard let image = capturedImage else {
            state = .error("No image captured.")
            return
        }

        // Cancel any in-flight upload
        uploadTask?.cancel()

        state = .uploading(progress: 0)

        uploadTask = Task { [weak self] in
            guard let self else { return }

            do {
                // ── Phase 1–3: Compress → Presign → Upload to S3 ──
                let uploaded = try await self.imageUploadService.upload(
                    image: image,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            // Map upload progress (0–1) into overall (0–0.8)
                            self?.state = .uploading(progress: progress * 0.8)
                        }
                    }
                )

                try Task.checkCancellation()

                // ── Phase 4: Create post record (server validates 24h rule) ──
                await MainActor.run {
                    self.state = .uploading(progress: 0.85)
                }

                let request = CreatePostRequest(
                    imageURL: uploaded.url,
                    imageWidth: uploaded.width,
                    imageHeight: uploaded.height,
                    imageSizeBytes: uploaded.sizeBytes,
                    tags: self.tags
                )

                let response = try await self.postService.createPost(request)

                try Task.checkCancellation()

                await MainActor.run {
                    self.state = .uploading(progress: 1.0)
                }

                // Brief pause so user sees 100%
                try? await Task.sleep(nanoseconds: 300_000_000)

                await MainActor.run {
                    self.state = .success(nextAllowedAt: response.nextPostAllowedAt)
                    // Release image memory immediately
                    self.capturedImage = nil
                }

            } catch is CancellationError {
                await MainActor.run {
                    self.state = .camera
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    self.state = .error(apiError.localizedDescription)
                }
            } catch let uploadError as UploadError {
                await MainActor.run {
                    self.state = .error(uploadError.localizedDescription)
                }
            } catch let compressionError as CompressionError {
                await MainActor.run {
                    self.state = .error(compressionError.localizedDescription)
                }
            } catch {
                await MainActor.run {
                    self.state = .error("Something went wrong. Please try again.")
                }
            }
        }
    }

    func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        state = .preview
    }

    func resetToCamera() {
        uploadTask?.cancel()
        uploadTask = nil
        capturedImage = nil
        tags = []
        tagLabel = ""
        tagURL = ""
        state = .camera
        camera.start()
    }
}
