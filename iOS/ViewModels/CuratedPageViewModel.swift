import Foundation
import UIKit

@MainActor
final class CuratedPageViewModel: ObservableObject {

    // MARK: - Question Pool

    static let questionPool: [String] = [
        "What's something you can't shut up about?",
        "A perfect day looks like...",
        "People come to me for...",
        "I'm currently obsessed with...",
        "My hot take is...",
        "The way to my heart is...",
        "I feel most alive when...",
        "Something most people don't know about me...",
        "My go-to comfort is...",
        "I believe everyone should try...",
        "My favorite way to spend a weekend...",
        "The best advice I ever got...",
        "I'm working on...",
        "What I value most in people...",
        "A song that defines me right now...",
        "My unpopular opinion is...",
    ]

    // MARK: - Published State

    @Published private(set) var page: CuratedPage?
    @Published private(set) var isLoading = false
    @Published var error: String?

    // Editing state
    @Published var images: [String?] = [nil, nil, nil, nil]
    @Published var qaSlots: [(prompt: String, answer: String)] = [
        ("", ""), ("", ""), ("", ""),("", "")
    ]
    @Published private(set) var isSaving = false

    // MARK: - Dependencies

    private let profileService: ProfileServiceProtocol
    private let imageUploadService: ImageUploadServiceProtocol
    let userID: UUID
    let isOwnProfile: Bool

    init(userID: UUID, isOwnProfile: Bool, profileService: ProfileServiceProtocol, imageUploadService: ImageUploadServiceProtocol) {
        self.userID = userID
        self.isOwnProfile = isOwnProfile
        self.profileService = profileService
        self.imageUploadService = imageUploadService
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        error = nil

        do {
            page = try await profileService.getCuratedPage(userID: userID)
            if let p = page {
                loadEditingState(from: p)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func loadEditingState(from p: CuratedPage) {
        images = [p.image1, p.image2, p.image3, p.image4]

        let pairs: [(String?, String?)] = [
            (p.q1Prompt, p.q1Answer),
            (p.q2Prompt, p.q2Answer),
            (p.q3Prompt, p.q3Answer),
            (p.q4Prompt, p.q4Answer),
        ]
        qaSlots = pairs.map { (prompt, answer) in
            (prompt ?? "", answer ?? "")
        }
    }

    // MARK: - Upload Image

    func uploadImage(at index: Int, image: UIImage) async {
        do {
            let uploaded = try await imageUploadService.upload(image: image, onProgress: { _ in })
            images[index] = uploaded.url
        } catch {
            self.error = "Failed to upload image."
        }
    }

    // MARK: - Save

    func save() async {
        isSaving = true
        error = nil

        let update = CuratedPageUpdate(
            p_image_1: images[0],
            p_image_2: images[1],
            p_image_3: images[2],
            p_image_4: images[3],
            p_q1_prompt: qaSlots[0].prompt.isEmpty ? nil : qaSlots[0].prompt,
            p_q1_answer: qaSlots[0].answer.isEmpty ? nil : qaSlots[0].answer,
            p_q2_prompt: qaSlots[1].prompt.isEmpty ? nil : qaSlots[1].prompt,
            p_q2_answer: qaSlots[1].answer.isEmpty ? nil : qaSlots[1].answer,
            p_q3_prompt: qaSlots[2].prompt.isEmpty ? nil : qaSlots[2].prompt,
            p_q3_answer: qaSlots[2].answer.isEmpty ? nil : qaSlots[2].answer,
            p_q4_prompt: qaSlots[3].prompt.isEmpty ? nil : qaSlots[3].prompt,
            p_q4_answer: qaSlots[3].answer.isEmpty ? nil : qaSlots[3].answer
        )

        do {
            try await profileService.upsertCuratedPage(update)
            await load()
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Helpers

    /// Questions not yet selected in any slot
    func availableQuestions(excludingIndex: Int) -> [String] {
        let selected = Set(qaSlots.enumerated().compactMap { i, slot in
            i == excludingIndex ? nil : (slot.prompt.isEmpty ? nil : slot.prompt)
        })
        return Self.questionPool.filter { !selected.contains($0) }
    }
}
