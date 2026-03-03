import SwiftUI

struct BlockedUsersView: View {

    let profileService: ProfileServiceProtocol

    @State private var users: [BlockedUser] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(users) { user in
                            blockedUserRow(user)
                        }
                    }
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBlockedUsers()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingM) {
            Image(systemName: "shield")
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(Theme.textTertiary)
            Text("No blocked users")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)
            Text("Users you block will appear here.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func blockedUserRow(_ user: BlockedUser) -> some View {
        HStack(spacing: 14) {
            CachedImageView(
                url: SupabaseConfig.storageURL(for: user.profilePhotoURL ?? ""),
                targetSize: CGSize(width: 96, height: 96)
            ) {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.custom("OpenSauceSans-SemiBold", size: 15))
                    .foregroundColor(Theme.textPrimary)

                if let name = user.displayName, !name.isEmpty {
                    Text(name)
                        .font(.custom("OpenSauceSans-Regular", size: 13))
                        .foregroundColor(Theme.textSecondary)
                }
            }

            Spacer()

            Button {
                Task { await unblock(user) }
            } label: {
                Text("Unblock")
                    .font(.custom("OpenSauceSans-Medium", size: 13))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.separator)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func loadBlockedUsers() async {
        isLoading = true
        do {
            users = try await profileService.getBlockedUsers()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func unblock(_ user: BlockedUser) async {
        do {
            try await profileService.unblockUser(targetUserID: user.id)
            withAnimation {
                users.removeAll { $0.id == user.id }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
