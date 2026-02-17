import SwiftUI

struct MainTabView: View {

    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Tab = .feed

    enum Tab: Hashable {
        case feed
        case search
        case post
        case profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            feedTab
            searchTab
            postTab
            profileTab
        }
        .tint(Theme.accent)
    }

    // MARK: - Tabs

    private var feedTab: some View {
        NavigationStack {
            FeedView(viewModel: appState.makeFeedViewModel())
                .navigationDestination(for: FeedPost.self) { post in
                    PostDetailView(
                        viewModel: appState.makePostDetailViewModel(post: post, commentsEnabled: false)
                    )
                }
        }
        .tabItem {
            Label("Feed", systemImage: "square.grid.2x2")
        }
        .tag(Tab.feed)
    }

    private var searchTab: some View {
        NavigationStack {
            SearchView(viewModel: appState.makeSearchViewModel()) { userID in
                // Navigation handled via navigationDestination
            }
            .navigationDestination(for: UUID.self) { userID in
                ProfileView(viewModel: appState.makeProfileViewModel(userID: userID))
            }
            .navigationDestination(for: ExplorePost.self) { post in
                PostDetailView(
                    viewModel: appState.makePostDetailViewModel(
                        post: post.asFeedPost,
                        commentsEnabled: true
                    )
                )
            }
        }
        .tabItem {
            Label("Search", systemImage: "magnifyingglass")
        }
        .tag(Tab.search)
    }

    private var postTab: some View {
        NavigationStack {
            PostCameraView(viewModel: appState.makePostViewModel())
        }
        .tabItem {
            Label("Post", systemImage: "camera")
        }
        .tag(Tab.post)
    }

    private var profileTab: some View {
        NavigationStack {
            if let userID = appState.authService.currentUserID {
                ProfileView(viewModel: appState.makeProfileViewModel(userID: userID))
            } else {
                Text("Please sign in")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .tabItem {
            Label("Profile", systemImage: "person")
        }
        .tag(Tab.profile)
    }
}
