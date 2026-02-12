import SwiftUI

struct FeedView: View {

    @StateObject var viewModel: FeedViewModel

    var body: some View {
        VStack(spacing: 0) {
            segmentedControl
            feedContent
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CURATED")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .tracking(2.0)
                    .foregroundColor(Theme.textPrimary)
            }
        }
        .task {
            await viewModel.loadInitial()
        }
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            ForEach(FeedSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedSegment = segment
                    }
                } label: {
                    VStack(spacing: Theme.spacingS) {
                        Text(segment.rawValue)
                            .font(Theme.headlineFont)
                            .foregroundColor(
                                viewModel.selectedSegment == segment
                                    ? Theme.textPrimary
                                    : Theme.textTertiary
                            )

                        Rectangle()
                            .fill(
                                viewModel.selectedSegment == segment
                                    ? Theme.accent
                                    : Color.clear
                            )
                            .frame(height: 1.5)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.top, Theme.spacingS)
        .background(Theme.background)
    }

    // MARK: - Feed Content

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.posts.isEmpty {
            Spacer()
            ProgressView()
                .tint(Theme.textTertiary)
            Spacer()
        } else if let error = viewModel.error, viewModel.posts.isEmpty {
            Spacer()
            errorView(error)
            Spacer()
        } else if viewModel.posts.isEmpty {
            Spacer()
            emptyView
            Spacer()
        } else {
            postList
        }
    }

    private var postList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spacingXL) {
                ForEach(viewModel.posts) { post in
                    NavigationLink(value: post) {
                        FeedPostCard(
                            post: post,
                            onLikeTapped: { Task { await viewModel.toggleLike(post: post) } },
                            onAuthorTapped: { /* Navigate to profile */ }
                        )
                    }
                    .buttonStyle(.plain)
                    .task {
                        await viewModel.loadMoreIfNeeded(currentPost: post)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .padding(.vertical, Theme.spacingL)
                }
            }
            .padding(.vertical, Theme.spacingL)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.spacingM) {
            Text("Nothing here yet")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)

            Text(viewModel.selectedSegment == .friends
                 ? "Follow people to see their posts."
                 : "Be the first to post today.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Theme.spacingM) {
            Text("Something went wrong")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)

            Text(message)
                .font(Theme.captionFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await viewModel.refresh() }
            }
            .font(Theme.headlineFont)
            .foregroundColor(Theme.accent)
        }
        .padding(.horizontal, Theme.spacingXL)
    }
}
