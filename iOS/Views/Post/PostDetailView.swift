import SwiftUI

struct PostDetailView: View {

    @StateObject var viewModel: PostDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                authorRow
                postImage
                actionsRow
                tagsSection
                if viewModel.commentsEnabled {
                    commentsSection
                }
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if viewModel.commentsEnabled {
                commentInputBar
            }
        }
        .task {
            await viewModel.loadComments()
        }
    }

    // MARK: - Author Row

    private var authorRow: some View {
        HStack(spacing: Theme.spacingS) {
            CachedImageView(
                url: SupabaseConfig.storageURL(for: viewModel.post.authorPhoto ?? ""),
                targetSize: CGSize(width: 72, height: 72)
            ) {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.post.username)
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)

                Text(viewModel.post.createdAt.timeAgo())
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingM)
    }

    // MARK: - Image

    private var postImage: some View {
        let aspect = CGFloat(viewModel.post.imageHeight) / max(1, CGFloat(viewModel.post.imageWidth))
        let screenWidth = UIScreen.main.bounds.width

        return CachedImageView(
            url: SupabaseConfig.storageURL(for: viewModel.post.imageURL),
            targetSize: CGSize(width: screenWidth, height: screenWidth * aspect)
        ) {
            Rectangle()
                .fill(Theme.background)
                .overlay { ProgressView().tint(Theme.textTertiary) }
        }
        .aspectRatio(1 / aspect, contentMode: .fit)
        .clipped()
    }

    // MARK: - Actions

    private var actionsRow: some View {
        HStack(spacing: Theme.spacingM) {
            Button {
                Task { await viewModel.toggleLike() }
            } label: {
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: viewModel.post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(viewModel.post.isLiked ? Theme.likeActive : Theme.textPrimary)

                    if viewModel.post.likeCount > 0 {
                        Text("\(viewModel.post.likeCount)")
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if viewModel.commentsEnabled {
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Theme.textPrimary)

                    if !viewModel.comments.isEmpty {
                        Text("\(viewModel.comments.count)")
                            .font(Theme.bodyFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingM)
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        if !viewModel.post.tags.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingS) {
                ForEach(viewModel.post.tags) { tag in
                    tagRow(tag)
                }
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.bottom, Theme.spacingL)
        }
    }

    private func tagRow(_ tag: Tag) -> some View {
        HStack(spacing: Theme.spacingS) {
            Text(tag.label)
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)

            if let urlString = tag.externalURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                        Text("Open")
                            .font(Theme.captionFont)
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .cornerRadius(Theme.radiusM)
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            Divider().background(Theme.separator)

            Text("COMMENTS")
                .font(Theme.sectionHeaderFont)
                .foregroundColor(Theme.textTertiary)
                .tracking(1.2)
                .padding(.horizontal, Theme.spacingM)

            if viewModel.isLoadingComments && viewModel.comments.isEmpty {
                ProgressView()
                    .tint(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.spacingL)
            } else if viewModel.comments.isEmpty {
                Text("No comments yet. Be the first!")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, Theme.spacingL)
            } else {
                ForEach(viewModel.comments) { comment in
                    commentRow(comment)
                }

                if viewModel.isLoadingComments {
                    ProgressView()
                        .tint(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacingS)
                }
            }
        }
        .padding(.bottom, 80) // Space for input bar
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingS) {
            CachedImageView(
                url: SupabaseConfig.storageURL(for: comment.authorPhoto ?? ""),
                targetSize: CGSize(width: 56, height: 56)
            ) {
                Circle()
                    .fill(Theme.separator)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                    }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.spacingXS) {
                    Text(comment.username)
                        .font(Theme.headlineFont)
                        .foregroundColor(Theme.textPrimary)

                    Text(comment.createdAt.timeAgo())
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textTertiary)
                }

                Text(comment.content)
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingXS)
    }

    // MARK: - Comment Input

    private var commentInputBar: some View {
        HStack(spacing: Theme.spacingS) {
            TextField("Add a comment...", text: $viewModel.commentText)
                .font(Theme.bodyFont)
                .textFieldStyle(.plain)

            Button {
                Task { await viewModel.sendComment() }
            } label: {
                if viewModel.isSendingComment {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(
                            viewModel.commentText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.textTertiary
                                : Theme.accent
                        )
                }
            }
            .disabled(viewModel.commentText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSendingComment)
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .background(.ultraThinMaterial)
    }
}
