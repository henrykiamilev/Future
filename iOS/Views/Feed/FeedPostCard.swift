import SwiftUI

struct FeedPostCard: View {

    let post: FeedPost
    let onLikeTapped: () -> Void
    let onReportTapped: () -> Void
    let onReactionTapped: (String) -> Void
    let reactions: [ReactionDisplay]
    let authorDestination: UUID

    @State private var showReactionPicker = false

    // Safe aspect ratio — guard against zero/negative/extreme dimensions
    private var imageAspect: CGFloat {
        guard post.imageWidth > 0, post.imageHeight > 0 else { return 1.25 }
        let raw = CGFloat(post.imageHeight) / CGFloat(post.imageWidth)
        // Clamp to reasonable range: 0.5 (wide landscape) to 2.0 (tall portrait)
        return min(max(raw, 0.5), 2.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Full-width image with overlays ──
            ZStack(alignment: .topLeading) {
                // Tap image → navigate to author profile
                NavigationLink(value: authorDestination) {
                    CachedImageView(
                        url: SupabaseConfig.storageURL(for: post.imageURL),
                        targetSize: CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * imageAspect)
                    ) {
                        Rectangle()
                            .fill(Theme.background)
                            .overlay { ProgressView().tint(Theme.textTertiary) }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1 / imageAspect, contentMode: .fill)
                    .clipped()
                }
                .buttonStyle(.plain)

                // ── Top gradient for text readability ──
                LinearGradient(
                    colors: [.black.opacity(0.5), .black.opacity(0.15), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .allowsHitTesting(false)

                // ── Bottom gradient ──
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                }
                .allowsHitTesting(false)

                // ── Top-left: avatar + username ──
                NavigationLink(value: authorDestination) {
                    HStack(spacing: 8) {
                        CachedImageView(
                            url: SupabaseConfig.storageURL(for: post.authorPhoto ?? ""),
                            targetSize: CGSize(width: 64, height: 64)
                        ) {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())

                        Text(post.username)
                            .font(Theme.headlineFont)
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 14)

                // ── Top-right: greeting + caption ──
                VStack(alignment: .trailing, spacing: 6) {
                    if let name = post.displayName, !name.isEmpty {
                        Text("HI \(name.uppercased())")
                            .font(.custom("OpenSauceSans-Light", size: 28))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                    }

                    if let caption = post.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.custom("OpenSauceSans-Regular", size: 15))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 50)
                .frame(maxWidth: .infinity, alignment: .trailing)

                // ── Bottom overlays: like + ellipsis ──
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        // Like button
                        Button(action: onLikeTapped) {
                            HStack(spacing: 5) {
                                Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundColor(post.isLiked ? Theme.likeActive : .white)

                                if post.likeCount > 0 {
                                    Text(formatCount(post.likeCount))
                                        .font(.custom("OpenSauceSans-Medium", size: 13))
                                        .foregroundColor(.white)
                                }
                            }
                            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in
                                    showReactionPicker = true
                                }
                        )

                        Spacer()

                        // Report / ellipsis
                        Button {
                            onReportTapped()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1 / imageAspect, contentMode: .fit)

            // ── Below image: location, tags, reactions, timestamp ──
            belowImageContent
        }
        .overlay(alignment: .bottomLeading) {
            if showReactionPicker {
                ReactionPicker(
                    onReact: { emoji in
                        showReactionPicker = false
                        onReactionTapped(emoji)
                    },
                    onDismiss: { showReactionPicker = false }
                )
                .padding(.leading, Theme.spacingM)
                .padding(.bottom, 60)
                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showReactionPicker)
        .onTapGesture {
            if showReactionPicker { showReactionPicker = false }
        }
    }

    // MARK: - Below Image Content

    @ViewBuilder
    private var belowImageContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Location
            if let location = post.location, !location.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textTertiary)

                    Text(location)
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            // Tags
            if !post.tags.isEmpty {
                HStack(spacing: Theme.spacingS) {
                    ForEach(post.tags) { tag in
                        tagChip(tag)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, post.location != nil ? 0 : 10)
            }

            // Reactions
            if !reactions.isEmpty {
                ReactionBar(reactions: reactions) { emoji in
                    onReactionTapped(emoji)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            // Timestamp
            Text(post.createdAt.timeAgo())
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Tags

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
