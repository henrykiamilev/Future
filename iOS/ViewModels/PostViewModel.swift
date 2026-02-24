import Foundation
import UIKit
import AVFoundation
import MapKit
import Combine

// ============================================================================
// POST VIEW MODEL
// ============================================================================
//
// State machine:
//   .needsPermission → .camera → .preview → .tagging → .uploading → .success
//                                   ↑  ↕                                 │
//                                   │ .editing (optional Darkroom)       │
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
        case editing
        case tagging
        case uploading(progress: Double)
        case success(nextAllowedAt: Date)
        case error(String)

        static func == (lhs: PostState, rhs: PostState) -> Bool {
            switch (lhs, rhs) {
            case (.needsPermission, .needsPermission): return true
            case (.camera, .camera): return true
            case (.preview, .preview): return true
            case (.editing, .editing): return true
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

    // Caption & Location
    @Published var caption: String = ""
    @Published var location: String = ""
    @Published var isDetectingLocation = false
    @Published var locationSearchResults: [MKLocalSearchCompletion] = []

    // Camera
    let camera = CameraCoordinator()

    // MARK: - Dependencies

    private let imageUploadService: ImageUploadServiceProtocol
    private let postService: PostServiceProtocol
    let locationService: LocationService
    private var uploadTask: Task<Void, Never>?
    private var locationSearchCancellable: AnyCancellable?

    init(imageUploadService: ImageUploadServiceProtocol, postService: PostServiceProtocol, locationService: LocationService) {
        self.imageUploadService = imageUploadService
        self.postService = postService
        self.locationService = locationService

        // Forward location service search results
        locationSearchCancellable = locationService.$searchResults
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                self?.locationSearchResults = results
            }
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
        print("[PostVM] capturePhoto() called — camera session running: \(camera.isSessionRunning)")
        guard camera.isSessionRunning else {
            print("[PostVM] Camera session not running — showing error")
            state = .error("Camera is not ready. Try switching tabs and coming back.")
            return
        }
        Task {
            do {
                let image = try await camera.capturePhoto()
                print("[PostVM] Photo captured successfully — size: \(image.size)")
                capturedImage = image
                state = .preview

                // Auto-detect location in background
                autoDetectLocation()
            } catch {
                print("[PostVM] Photo capture FAILED: \(error)")
                state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Location

    func autoDetectLocation() {
        isDetectingLocation = true
        Task {
            do {
                let detected = try await locationService.requestCurrentLocation()
                location = detected
            } catch {
                print("[PostVM] Location auto-detect failed: \(error.localizedDescription)")
                // Non-fatal — user can type manually
            }
            isDetectingLocation = false
        }
    }

    func updateLocationSearch(query: String) {
        locationService.updateSearch(query: query)
    }

    func selectLocationResult(_ completion: MKLocalSearchCompletion) {
        Task {
            let resolved = await locationService.resolveCompletion(completion)
            location = resolved
            locationSearchResults = []
            locationService.updateSearch(query: "")
        }
    }

    func retakePhoto() {
        capturedImage = nil
        tags = []
        tagLabel = ""
        tagURL = ""
        caption = ""
        location = ""
        locationSearchResults = []
        state = .camera
        camera.start()
    }

    func openDarkroom() {
        state = .editing
    }

    func finishEditing(editedImage: UIImage) {
        capturedImage = editedImage
        state = .preview
    }

    func cancelEditing() {
        state = .preview
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

                let trimmedCaption = self.caption.trimmingCharacters(in: .whitespaces)
                let trimmedLocation = self.location.trimmingCharacters(in: .whitespaces)

                let request = CreatePostRequest(
                    imageURL: uploaded.url,
                    imageWidth: uploaded.width,
                    imageHeight: uploaded.height,
                    imageSizeBytes: uploaded.sizeBytes,
                    tags: self.tags,
                    caption: trimmedCaption.isEmpty ? nil : trimmedCaption,
                    location: trimmedLocation.isEmpty ? nil : trimmedLocation
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
        caption = ""
        location = ""
        locationSearchResults = []
        state = .camera
        camera.start()
    }
}
