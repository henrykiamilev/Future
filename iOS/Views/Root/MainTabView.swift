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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NotificationBellButton(viewModel: appState.makeNotificationViewModel())
                            .colorScheme(.dark) // White icon over photo
                            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                    }
                }
                .navigationDestination(for: FeedPost.self) { post in
                    PostDetailView(
                        viewModel: appState.makePostDetailViewModel(post: post, commentsEnabled: true)
                    )
                }
                .navigationDestination(for: UUID.self) { userID in
                    ProfileView(viewModel: appState.makeProfileViewModel(userID: userID))
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

// MARK: - Notification Bell Button

struct NotificationBellButton: View {

    @ObservedObject var viewModel: NotificationViewModel
    @State private var showNotifications = false

    var body: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                if viewModel.unreadCount > 0 {
                    Text(viewModel.unreadCount > 9 ? "9+" : "\(viewModel.unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.likeActive)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .navigationDestination(isPresented: $showNotifications) {
            NotificationView(viewModel: viewModel)
        }
        .task {
            await viewModel.refreshUnreadCount()
        }
    }
}
