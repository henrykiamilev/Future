import Foundation
import UIKit
import AVFoundation

@MainActor
final class PostViewModel: ObservableObject {

    enum PostState: Equatable {
        case camera
        case preview
        case tagging
        case uploading
        case success(nextAllowedAt: Date)
        case error(String)
    }

    // MARK: - Published State

    @Published private(set) var state: PostState = .camera
    @Published var capturedImage: UIImage?
    @Published var tags: [TagInput] = []
    @Published private(set) var uploadProgress: Double = 0

    // Tag input
    @Published var tagLabel: String = ""
    @Published var tagURL: String = ""

    // MARK: - Dependencies

    private let imageUploadService: ImageUploadServiceProtocol
    private let postService: PostServiceProtocol

    init(imageUploadService: ImageUploadServiceProtocol, postService: PostServiceProtocol) {
        self.imageUploadService = imageUploadService
        self.postService = postService
    }

    // MARK: - Camera Authorization

    var cameraAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Capture Flow

    func onPhotoCaptured(_ image: UIImage) {
        capturedImage = image
        state = .preview
    }

    func retakePhoto() {
        capturedImage = nil
        tags = []
        tagLabel = ""
        tagURL = ""
        state = .camera
    }

    func proceedToTagging() {
        state = .tagging
    }

    // MARK: - Tag Management

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

    // MARK: - Upload

    func submitPost() async {
        guard let image = capturedImage else {
            state = .error("No image captured.")
            return
        }

        state = .uploading
        uploadProgress = 0.1

        do {
            // 1. Upload image
            let uploaded = try await imageUploadService.upload(image: image)
            uploadProgress = 0.6

            // 2. Validate server-side constraints locally for fast feedback
            guard uploaded.sizeBytes <= 2_621_440 else {
                state = .error("Image too large after compression. Try again.")
                return
            }

            // 3. Create post (server enforces 24h rule, constraints)
            let request = CreatePostRequest(
                imageURL: uploaded.url,
                imageWidth: uploaded.width,
                imageHeight: uploaded.height,
                imageSizeBytes: uploaded.sizeBytes,
                tags: tags
            )

            let response = try await postService.createPost(request)
            uploadProgress = 1.0
            state = .success(nextAllowedAt: response.nextPostAllowedAt)

        } catch let apiError as APIError {
            state = .error(apiError.localizedDescription)
        } catch {
            state = .error("Upload failed. Please try again.")
        }
    }

    func resetToCamera() {
        capturedImage = nil
        tags = []
        tagLabel = ""
        tagURL = ""
        uploadProgress = 0
        state = .camera
    }
}
