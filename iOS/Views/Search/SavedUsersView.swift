import SwiftUI

struct SavedUsersView: View {

    @StateObject var viewModel: SavedUsersViewModel
    let onUserTapped: (UUID) -> Void

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .tint(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.users.isEmpty {
                emptyState
            } else {
                userList
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SAVED")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(2.0)
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - List

    private var userList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.users) { user in
                    userRow(user)
                }
            }
        }
    }

    private func userRow(_ user: SuggestedUser) -> some View {
        Button {
            onUserTapped(user.id)
        } label: {
            HStack(spacing: Theme.spacingM) {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: user.profilePhotoURL ?? ""),
                    targetSize: CGSize(width: 88, height: 88)
                ) {
                    Circle()
                        .fill(Theme.separator)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Theme.textTertiary)
                        }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.textPrimary)

                    if let name = user.displayName, !name.isEmpty {
                        Text(name)
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                Spacer()

                // Unsave button
                Button {
                    viewModel.unsave(userID: user.id)
                } label: {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.vertical, Theme.spacingM)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: Theme.spacingS) {
            Image(systemName: "bookmark")
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(Theme.textTertiary)
            Text("No saved people yet")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)
            Text("Swipe up on a card in Shuffle to save someone for later.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.spacingXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ViewModel

@MainActor
final class SavedUsersViewModel: ObservableObject {

    @Published var users: [SuggestedUser] = []
    @Published var isLoading = false

    private let shuffleService: ShuffleServiceProtocol

    init(shuffleService: ShuffleServiceProtocol) {
        self.shuffleService = shuffleService
    }

    func load() async {
        isLoading = true
        do {
            users = try await shuffleService.fetchSavedUsers(limit: 50)
        } catch {
            users = []
        }
        isLoading = false
    }

    func unsave(userID: UUID) {
        users.removeAll { $0.id == userID }
        Task {
            try? await shuffleService.unsaveUser(userID: userID)
        }
    }
}
