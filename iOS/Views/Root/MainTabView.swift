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
        ZStack(alignment: .bottom) {
            // ── Tab content ──
            Group {
                switch selectedTab {
                case .feed:
                    feedTab
                case .search:
                    searchTab
                case .post:
                    postTab
                case .profile:
                    profileTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Custom compact tab bar ──
            customTabBar
        }
    }

    // MARK: - Custom Tab Bar

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabIcon(tab: .feed, icon: "house", filledIcon: "house.fill")
            tabIcon(tab: .search, icon: "magnifyingglass", filledIcon: "magnifyingglass")
            tabIcon(tab: .post, icon: "plus.app", filledIcon: "plus.app.fill")
            tabIcon(tab: .profile, icon: "person.circle", filledIcon: "person.circle.fill")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        )
        .padding(.horizontal, 32)
        .padding(.bottom, 4)
    }

    private func tabIcon(tab: Tab, icon: String, filledIcon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            Image(systemName: selectedTab == tab ? filledIcon : icon)
                .font(.system(size: 22, weight: selectedTab == tab ? .medium : .light))
                .foregroundColor(selectedTab == tab ? Theme.textPrimary : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tabs

    private var feedTab: some View {
        NavigationStack {
            FeedView(viewModel: appState.makeFeedViewModel())
                .navigationDestination(for: FeedPost.self) { post in
                    PostDetailView(
                        viewModel: appState.makePostDetailViewModel(post: post, commentsEnabled: true)
                    )
                }
                .navigationDestination(for: UUID.self) { userID in
                    ProfileView(viewModel: appState.makeProfileViewModel(userID: userID))
                }
        }
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
    }

    private var postTab: some View {
        NavigationStack {
            PostCameraView(viewModel: appState.makePostViewModel())
        }
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
