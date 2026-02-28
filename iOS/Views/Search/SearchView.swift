import SwiftUI

struct SearchView: View {

    @StateObject var viewModel: SearchViewModel
    let onUserTapped: (UUID) -> Void

    private let exploreColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Greeting + search bar
            VStack(spacing: 6) {
                Text("Discover your community")
                    .font(.custom("OpenSauceSans-Regular", size: 13))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)

                searchBar
            }

            resultsList
        }
        .background(Theme.background)
        .navigationBarHidden(true)
        .task {
            await viewModel.loadDiscover()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.textTertiary)

            TextField("Search people", text: $viewModel.query)
                .font(.custom("OpenSauceSans-Regular", size: 15))
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
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
                    .font(.custom("OpenSauceSans-Medium", size: 16))
                    .foregroundColor(Theme.textPrimary)
                Text(error)
                    .font(.custom("OpenSauceSans-Regular", size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.spacingXL)
            Spacer()
        } else if viewModel.results.isEmpty && viewModel.hasSearched {
            Spacer()
            VStack(spacing: Theme.spacingS) {
                Text("No users found")
                    .font(.custom("OpenSauceSans-Medium", size: 16))
                    .foregroundColor(Theme.textPrimary)
                Text("Try a different search.")
                    .font(.custom("OpenSauceSans-Regular", size: 14))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        } else if viewModel.results.isEmpty {
            discoverSection
        } else {
            searchResultsList
        }
    }

    // MARK: - Search Results List

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.results) { user in
                    userRow(user)
                }
                Spacer().frame(height: 80)
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
                    // New to Curated — featured new member cards
                    if !viewModel.suggestedUsers.isEmpty {
                        newToCuratedSection
                    }

                    // People you might like — rich horizontal cards
                    if !viewModel.suggestedUsers.isEmpty {
                        suggestedUsersSection
                    }

                    // Trending posts grid
                    if !viewModel.explorePosts.isEmpty {
                        trendingPostsSection
                    }

                    // Empty fallback
                    if viewModel.suggestedUsers.isEmpty && viewModel.explorePosts.isEmpty {
                        VStack(spacing: Theme.spacingM) {
                            Image(systemName: "person.2")
                                .font(.system(size: 40, weight: .ultraLight))
                                .foregroundColor(Theme.textTertiary)
                            Text("Find people")
                                .font(.custom("OpenSauceSans-SemiBold", size: 18))
                                .foregroundColor(Theme.textPrimary)
                            Text("Search by username to discover new accounts.")
                                .font(.custom("OpenSauceSans-Regular", size: 14))
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.spacingXXL)
                        .padding(.horizontal, Theme.spacingXL)
                    }
                }

                Spacer().frame(height: 80)
            }
        }
    }

    // MARK: - New to Curated (Featured member cards)

    private var newToCuratedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New to Curated")
                .font(.custom("OpenSauceSans-SemiBold", size: 16))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.suggestedUsers) { user in
                        NavigationLink(value: user.id) {
                            newMemberCard(user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private func newMemberCard(_ user: SuggestedUser) -> some View {
        VStack(spacing: 0) {
            // Profile photo — large rounded rectangle
            CachedImageView(
                url: SupabaseConfig.storageURL(for: user.profilePhotoURL ?? ""),
                targetSize: CGSize(width: 280, height: 340)
            ) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 36))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 140, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)

            // Info below the photo
            VStack(spacing: 3) {
                Text(user.username)
                    .font(.custom("OpenSauceSans-SemiBold", size: 14))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                if let name = user.displayName, !name.isEmpty {
                    Text(name)
                        .font(.custom("OpenSauceSans-Regular", size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }

                Text("\(user.followerCount) followers")
                    .font(.custom("OpenSauceSans-Regular", size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.top, 12)
        }
        .frame(width: 140)
    }

    // MARK: - People You Might Like (Rich horizontal cards)

    private var suggestedUsersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("People you might like")
                .font(.custom("OpenSauceSans-SemiBold", size: 16))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.suggestedUsers) { user in
                        NavigationLink(value: user.id) {
                            suggestedRichCard(user)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 28)
    }

    private func suggestedRichCard(_ user: SuggestedUser) -> some View {
        VStack(spacing: 0) {
            // Top: profile photo + info
            HStack(spacing: 12) {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: user.profilePhotoURL ?? ""),
                    targetSize: CGSize(width: 96, height: 96)
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
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(.custom("OpenSauceSans-SemiBold", size: 14))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    Text(formatFollowers(user.followerCount))
                        .font(.custom("OpenSauceSans-Regular", size: 11))
                        .foregroundColor(Theme.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Bottom: preview of their latest post (use their profile photo as stand-in)
            CachedImageView(
                url: SupabaseConfig.storageURL(for: user.profilePhotoURL ?? ""),
                targetSize: CGSize(width: 320, height: 200)
            ) {
                Rectangle()
                    .fill(Theme.separator)
            }
            .frame(height: 120)
            .clipped()
        }
        .frame(width: 220)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    // MARK: - Trending Posts

    private var trendingPostsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Trending")
                .font(.custom("OpenSauceSans-SemiBold", size: 16))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 20)

            LazyVGrid(columns: exploreColumns, spacing: 3) {
                ForEach(viewModel.explorePosts) { post in
                    NavigationLink(value: post) {
                        exploreTile(post)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 3)
        }
        .padding(.bottom, 24)
    }

    private func exploreTile(_ post: ExplorePost) -> some View {
        let size = (UIScreen.main.bounds.width - 9) / 2

        return ZStack(alignment: .bottomLeading) {
            CachedImageView(
                url: SupabaseConfig.storageURL(for: post.imageURL),
                targetSize: CGSize(width: size * 2, height: size * 2)
            ) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.separator)
            }
            .frame(width: size, height: size * 1.2)
            .clipped()

            // Bottom gradient
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.4), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Username overlay
            Text(post.username)
                .font(.custom("OpenSauceSans-Medium", size: 12))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Search Result Row

    private func userRow(_ user: UserSummary) -> some View {
        NavigationLink(value: user.id) {
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

                VStack(alignment: .leading, spacing: 3) {
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
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
