import SwiftUI

struct FeedPostCard: View {

    let post: FeedPost
    let onLikeTapped: () -> Void
    let authorDestination: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            authorRow
            postImage
            actionsRow
            tagsRow
        }
        .background(Theme.surface)
    }

    // MARK: - Author Row

    private var authorRow: some View {
        NavigationLink(value: authorDestination) {
            HStack(spacing: Theme.spacingS) {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: post.authorPhoto ?? ""),
                    targetSize: CGSize(width: 64, height: 64)
                ) {
                    Circle()
                        .fill(Theme.separator)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textTertiary)
                        }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())

                Text(post.username)
                    .font(Theme.headlineFont)
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Text(post.createdAt.timeAgo())
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, Theme.spacingS + 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Image

    private var postImage: some View {
        let aspect = CGFloat(post.imageHeight) / max(1, CGFloat(post.imageWidth))

        return GeometryReader { geometry in
            NavigationLink(value: post) {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: post.imageURL),
                    targetSize: CGSize(width: geometry.size.width, height: geometry.size.width * aspect)
                ) {
                    Rectangle()
                        .fill(Theme.background)
                        .overlay { ProgressView().tint(Theme.textTertiary) }
                }
                .aspectRatio(1 / aspect, contentMode: .fit)
                .clipped()
            }
            .buttonStyle(.plain)
        }
        .aspectRatio(1 / aspect, contentMode: .fit)
    }

    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: Theme.spacingM) {
            // Like button
            Button(action: onLikeTapped) {
                HStack(spacing: Theme.spacingXS) {
                    Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(post.isLiked ? Theme.likeActive : Theme.textPrimary)

                    if post.likeCount > 0 {
                        Text(formatCount(post.likeCount))
                            .font(Theme.captionFont)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS + 2)
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsRow: some View {
        if !post.tags.isEmpty {
            HStack(spacing: Theme.spacingS) {
                ForEach(post.tags) { tag in
                    tagChip(tag)
                }
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.bottom, Theme.spacingS + 2)
        }
    }

    private func tagChip(_ tag: Tag) -> some View {
        Group {
            if let urlString = tag.externalURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    tagLabel(tag.label, hasLink: true)
                }
            } else {
                tagLabel(tag.label, hasLink: false)
            }
        }
    }

    private func tagLabel(_ text: String, hasLink: Bool) -> some View {
        Text(text)
            .font(Theme.labelFont)
            .foregroundColor(hasLink ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, Theme.spacingS)
            .padding(.vertical, Theme.spacingXS)
            .background(Theme.background)
            .cornerRadius(Theme.radiusS)
    }

    // MARK: - Helpers

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgo() -> String {
        let seconds = Int(Date().timeIntervalSince(self))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
