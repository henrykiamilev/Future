import SwiftUI

struct FeedPostCard: View {

    let post: FeedPost
    let onLikeTapped: () -> Void
    let onReportTapped: () -> Void
    let onReactionTapped: (String) -> Void
    let reactions: [ReactionDisplay]
    let authorDestination: UUID

    @State private var showReactionPicker = false

    private let screenWidth = UIScreen.main.bounds.width

    // Image fills most of the viewport — clamp aspect to keep it sane
    private var imageAspect: CGFloat {
        guard post.imageWidth > 0, post.imageHeight > 0 else { return 1.33 }
        let raw = CGFloat(post.imageHeight) / CGFloat(post.imageWidth)
        return min(max(raw, 0.75), 1.6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Image area with overlays ──
            imageSection

            // ── Below image: location, tags, actions ──
            footerSection
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
                .padding(.bottom, 80)
                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showReactionPicker)
        .onTapGesture {
            if showReactionPicker { showReactionPicker = false }
        }
    }

    // MARK: - Image Section (full-width with overlays)

    private var imageSection: some View {
        ZStack {
            // Background image — tappable to go to profile
            NavigationLink(value: authorDestination) {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: post.imageURL),
                    targetSize: CGSize(width: screenWidth, height: screenWidth * imageAspect)
                ) {
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .overlay { ProgressView().tint(.white.opacity(0.5)) }
                }
                .frame(width: screenWidth, height: screenWidth * imageAspect)
                .clipped()
            }
            .buttonStyle(.plain)

            // ── Top gradient ──
            VStack {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .black.opacity(0.2), location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                Spacer()
            }
            .allowsHitTesting(false)

            // ── Top-left: avatar (square, rounded) ──
            VStack {
                HStack {
                    NavigationLink(value: authorDestination) {
                        CachedImageView(
                            url: SupabaseConfig.storageURL(for: post.authorPhoto ?? ""),
                            targetSize: CGSize(width: 100, height: 100)
                        ) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.15))
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 14)
            .padding(.top, 14)

            // ── Top-right: HI [NAME] + caption ──
            VStack {
                HStack {
                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if let name = post.displayName, !name.isEmpty {
                            Text(name.uppercased())
                                .font(.custom("OpenSauceSans-Light", size: 24))
                                .foregroundColor(.white)
                        } else {
                            Text(post.username.uppercased())
                                .font(.custom("OpenSauceSans-Light", size: 24))
                                .foregroundColor(.white)
                        }

                        if let caption = post.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.custom("OpenSauceSans-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        }
                    }
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                }
                Spacer()
            }
            .padding(.trailing, 14)
            .padding(.top, 16)

            // ── Bottom: like + ellipsis (over image) ──
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
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .onEnded { _ in showReactionPicker = true }
                    )

                    Spacer()

                    // Report / ellipsis
                    Button { onReportTapped() } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(width: screenWidth, height: screenWidth * imageAspect)
    }

    // MARK: - Footer Section (below image, light background)

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            }

            // Tags
            if !post.tags.isEmpty {
                HStack(spacing: Theme.spacingS) {
                    ForEach(post.tags) { tag in
                        tagChip(tag)
                    }
                }
            }

            // Reactions
            if !reactions.isEmpty {
                ReactionBar(reactions: reactions) { emoji in
                    onReactionTapped(emoji)
                }
            }

            // Timestamp
            Text(post.createdAt.timeAgo())
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
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
            .background(Theme.surface)
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
