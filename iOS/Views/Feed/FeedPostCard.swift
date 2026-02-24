import SwiftUI

struct FeedPostCard: View {

    let post: FeedPost
    let onLikeTapped: () -> Void
    let onReportTapped: () -> Void
    let onReactionTapped: (String) -> Void
    let reactions: [ReactionDisplay]
    let authorDestination: UUID

    @State private var showReactionPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Edge-to-edge image with overlays
            imageWithOverlays

            // Below-image content: location, tags, reactions
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

    // MARK: - Image with Overlays

    private var imageWithOverlays: some View {
        let aspect = CGFloat(post.imageHeight) / max(1, CGFloat(post.imageWidth))

        return GeometryReader { geometry in
            ZStack {
                // Tap → profile navigation
                NavigationLink(value: authorDestination) {
                    CachedImageView(
                        url: SupabaseConfig.storageURL(for: post.imageURL),
                        targetSize: CGSize(width: geometry.size.width, height: geometry.size.width * aspect)
                    ) {
                        Rectangle()
                            .fill(Theme.background)
                            .overlay { ProgressView().tint(Theme.textTertiary) }
                    }
                    .aspectRatio(1 / aspect, contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.width * aspect)
                    .clipped()
                }
                .buttonStyle(.plain)

                // Top gradient for text readability
                VStack {
                    LinearGradient(
                        colors: [.black.opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    Spacer()
                }

                // Bottom gradient for actions
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.50)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }

                // Top-left: avatar + username pill
                VStack {
                    HStack {
                        NavigationLink(value: authorDestination) {
                            HStack(spacing: 6) {
                                CachedImageView(
                                    url: SupabaseConfig.storageURL(for: post.authorPhoto ?? ""),
                                    targetSize: CGSize(width: 48, height: 48)
                                ) {
                                    Circle()
                                        .fill(Color.white.opacity(0.3))
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 9))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())

                                Text(post.username)
                                    .font(Theme.labelFont)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.leading, Theme.spacingM)
                    .padding(.top, Theme.spacingM)

                    Spacer()
                }

                // Top-right: greeting + caption
                VStack {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let name = post.displayName, !name.isEmpty {
                            Text("HI \(name.uppercased())")
                                .font(Theme.greetingFont)
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                        }

                        if let caption = post.caption, !caption.isEmpty {
                            Text(caption)
                                .font(Theme.bodyFont)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.trailing)
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, Theme.spacingM)
                    .padding(.top, Theme.spacingXL + Theme.spacingM)

                    Spacer()
                }

                // Bottom-left: like button
                VStack {
                    Spacer()
                    HStack {
                        Button(action: onLikeTapped) {
                            HStack(spacing: 4) {
                                Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(post.isLiked ? Theme.likeActive : .white)

                                if post.likeCount > 0 {
                                    Text(formatCount(post.likeCount))
                                        .font(Theme.labelFont)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.4)
                                .onEnded { _ in
                                    showReactionPicker = true
                                }
                        )

                        Spacer()

                        // Bottom-right: report (ellipsis)
                        Button {
                            onReportTapped()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.bottom, Theme.spacingM)
                }
            }
        }
        .aspectRatio(1 / aspect, contentMode: .fit)
    }

    // MARK: - Below Image Content

    @ViewBuilder
    private var belowImageContent: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
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
                .padding(.horizontal, Theme.spacingM)
                .padding(.top, Theme.spacingS)
            }

            // Tags
            if !post.tags.isEmpty {
                HStack(spacing: Theme.spacingS) {
                    ForEach(post.tags) { tag in
                        tagChip(tag)
                    }
                }
                .padding(.horizontal, Theme.spacingM)
                .padding(.top, post.location != nil ? 0 : Theme.spacingS)
            }

            // Reactions
            if !reactions.isEmpty {
                ReactionBar(reactions: reactions) { emoji in
                    onReactionTapped(emoji)
                }
                .padding(.horizontal, Theme.spacingM)
                .padding(.top, Theme.spacingXS)
            }

            // Timestamp
            Text(post.createdAt.timeAgo())
                .font(Theme.captionFont)
                .foregroundColor(Theme.textTertiary)
                .padding(.horizontal, Theme.spacingM)
                .padding(.top, Theme.spacingXS)
        }
        .padding(.bottom, Theme.spacingS)
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
