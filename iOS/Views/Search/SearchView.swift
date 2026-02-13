import SwiftUI

struct SearchView: View {

    @StateObject var viewModel: SearchViewModel
    let onUserTapped: (UUID) -> Void

    private let exploreColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            resultsList
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("DISCOVER")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(2.0)
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .task {
            await viewModel.loadDiscover()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(Theme.textTertiary)

            TextField("Search users...", text: $viewModel.query)
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: viewModel.query) { _, _ in
                    viewModel.onQueryChanged()
                }

            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    viewModel.onQueryChanged()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .cornerRadius(Theme.radiusM)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusM)
                .strokeBorder(Theme.separator.opacity(0.6), lineWidth: 1)
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, Theme.spacingM)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if viewModel.isSearching {
            Spacer()
            ProgressView()
                .tint(Theme.textTertiary)
            Spacer()
        } else if let error = viewModel.error {
            Spacer()
            VStack(spacing: Theme.spacingS) {
                Text("Search failed")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                Text(error)
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.spacingXL)
            Spacer()
        } else if viewModel.results.isEmpty && viewModel.hasSearched {
            Spacer()
            VStack(spacing: Theme.spacingS) {
                Text("No users found")
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)
                Text("Try a different search.")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        } else if viewModel.results.isEmpty {
            discoverSection
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.results) { user in
                        userRow(user)
                    }
                }
            }
        }
    }

    // MARK: - Discover Section

    private var discoverSection: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isLoadingDiscover {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.spacingXXL)
                } else {
                    // Suggested users
                    if !viewModel.suggestedUsers.isEmpty {
                        suggestedUsersSection
                    }

                    // Trending posts
                    if !viewModel.explorePosts.isEmpty {
                        trendingPostsSection
                    }

                    // Empty fallback
                    if viewModel.suggestedUsers.isEmpty && viewModel.explorePosts.isEmpty {
                        VStack(spacing: Theme.spacingS) {
                            Image(systemName: "person.2")
                                .font(.system(size: 36, weight: .thin))
                                .foregroundColor(Theme.textTertiary)
                            Text("Find people")
                                .font(Theme.headlineFont)
                                .foregroundColor(Theme.textPrimary)
                            Text("Search by username to discover new accounts.")
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.spacingXXL)
                        .padding(.horizontal, Theme.spacingXL)
                    }
                }
            }
        }
    }

    // MARK: - Suggested Users

    private var suggestedUsersSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            Text("SUGGESTED")
                .font(Theme.sectionHeaderFont)
                .foregroundColor(Theme.textTertiary)
                .tracking(1.5)
                .padding(.horizontal, Theme.spacingL)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacingM) {
                    ForEach(viewModel.suggestedUsers) { user in
                        NavigationLink(value: user.id) {
                            suggestedUserCard(user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.spacingL)
            }
        }
        .padding(.top, Theme.spacingS)
        .padding(.bottom, Theme.spacingXL)
    }

    private func suggestedUserCard(_ user: SuggestedUser) -> some View {
        VStack(spacing: Theme.spacingS) {
            CachedImageView(
                url: URL(string: user.profilePhotoURL ?? ""),
                targetSize: CGSize(width: 64, height: 64)
            ) {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())

            Text(user.username)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            Text(formatFollowers(user.followerCount))
                .font(Theme.labelFont)
                .foregroundColor(Theme.textTertiary)
        }
        .frame(width: 80)
    }

    // MARK: - Trending Posts

    private var trendingPostsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            Text("TRENDING")
                .font(Theme.sectionHeaderFont)
                .foregroundColor(Theme.textTertiary)
                .tracking(1.5)
                .padding(.horizontal, Theme.spacingL)

            LazyVGrid(columns: exploreColumns, spacing: 2) {
                ForEach(viewModel.explorePosts) { post in
                    NavigationLink(value: post) {
                        exploreTile(post)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func exploreTile(_ post: ExplorePost) -> some View {
        let size = (UIScreen.main.bounds.width - 4) / 2

        return CachedImageView(
            url: URL(string: post.imageURL),
            targetSize: CGSize(width: size, height: size)
        ) {
            Rectangle().fill(Theme.separator)
        }
        .scaledToFill()
        .frame(width: size, height: size)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if post.likeCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                    Text(formatCount(post.likeCount))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .cornerRadius(Theme.radiusS)
                .padding(6)
            }
        }
    }

    // MARK: - Search Result Row

    private func userRow(_ user: UserSummary) -> some View {
        NavigationLink(value: user.id) {
            HStack(spacing: Theme.spacingM) {
                CachedImageView(
                    url: URL(string: user.profilePhotoURL ?? ""),
                    targetSize: CGSize(width: 44, height: 44)
                ) {
                    Circle()
                        .fill(Theme.separator)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.vertical, Theme.spacingM)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatFollowers(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count) followers"
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
