import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// FeedPostCard — Tall Rounded Rectangle Card
// ═══════════════════════════════════════════════════════════════════════════
//
// Layout:
//   ┌───────────────────────────────────────┐
//   │                                       │
//   │  ┌─────────────────────────────────┐  │  ← cream background
//   │  │                                 │  │
//   │  │     PHOTO (aspect-fill)         │  │  ← tall rounded rect
//   │  │                                 │  │
//   │  │                                 │  │
//   │  │                                 │  │
//   │  │                                 │  │
//   │  │                                 │  │
//   │  │                                 │  │
//   │  └─────────────────────────────────┘  │
//   │                                       │
//   │  username                  React btn  │
//   │                                       │
//   └───────────────────────────────────────┘
//
// Tap → expands to full-screen (Instagram Reels style)
//
// ═══════════════════════════════════════════════════════════════════════════

struct FeedPostCard: View {

    let post: FeedPost
    let onReactTapped: () -> Void
    let onTap: () -> Void

    // MARK: - Layout

    private let screenWidth = UIScreen.main.bounds.width
    private let horizontalPadding: CGFloat = 20
    private let cornerRadius: CGFloat = 18

    private var cardWidth: CGFloat {
        screenWidth - (horizontalPadding * 2)
    }

    /// Tall portrait rectangle — aspect ratio ~1.45 (height/width)
    private var imageHeight: CGFloat {
        cardWidth * 1.45
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Rounded image card ──
            imageCard

            // ── Info row below card ──
            infoRow
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 24)
    }

    // MARK: - Image Card (tall rounded rectangle)

    private var imageCard: some View {
        Button(action: onTap) {
            CachedImageView(
                url: SupabaseConfig.storageURL(for: post.imageURL),
                targetSize: CGSize(width: cardWidth * 2, height: imageHeight * 2)
            ) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(white: 0.92))
                    .overlay {
                        ProgressView()
                            .tint(Theme.textTertiary)
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: cardWidth, height: imageHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info Row (username + react)

    private var infoRow: some View {
        HStack(alignment: .center) {
            Text(displayName)
                .font(.custom("OpenSauceSans-Medium", size: 14))
                .foregroundColor(FeedTokens.textPrimary)
                .lineLimit(1)

            Spacer()

            Button(action: onReactTapped) {
                Text("React")
                    .font(.custom("OpenSauceSans-Medium", size: 13))
                    .foregroundColor(FeedTokens.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(FeedTokens.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

    private var displayName: String {
        if let name = post.displayName, !name.isEmpty { return name }
        return post.username
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// FeedFullScreenView — Full-screen photo expansion (Instagram Reels style)
// ═══════════════════════════════════════════════════════════════════════════

struct FeedFullScreenView: View {

    let post: FeedPost
    let onDismiss: () -> Void
    let onProfileTapped: () -> Void

    private let screenWidth = UIScreen.main.bounds.width
    private let screenHeight = UIScreen.main.bounds.height

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()

            // Full-screen image
            CachedImageView(
                url: SupabaseConfig.storageURL(for: post.imageURL),
                targetSize: CGSize(width: screenWidth * 2, height: screenHeight * 2)
            ) {
                Rectangle()
                    .fill(Color(white: 0.08))
                    .overlay {
                        ProgressView().tint(.white.opacity(0.3))
                    }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: screenWidth, height: screenHeight)
            .clipped()
            .ignoresSafeArea()

            // Bottom gradient for readability
            VStack {
                Spacer()
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.6), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Overlay content — bottom info only
            VStack {
                Spacer()

                // Bottom info
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Username
                        Button(action: onProfileTapped) {
                            Text(displayName)
                                .font(.custom("OpenSauceSans-SemiBold", size: 16))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)

                        // Caption
                        if let caption = post.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.custom("OpenSauceSans-Regular", size: 14))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(3)
                        }

                        // Location
                        if let location = post.location, !location.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 10))
                                Text(location)
                                    .font(.custom("OpenSauceSans-Regular", size: 12))
                            }
                            .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 150 {
                        onDismiss()
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }

    private var displayName: String {
        if let name = post.displayName, !name.isEmpty { return name }
        return post.username
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feed Design Tokens
// ═══════════════════════════════════════════════════════════════════════════

enum FeedTokens {
    static let panelBackground = Color(red: 0.961, green: 0.961, blue: 0.953)  // #F5F5F3
    static let textPrimary = Color(red: 0.067, green: 0.067, blue: 0.067)      // #111
    static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.45)       // #737373
    static let border = Color(red: 0.855, green: 0.855, blue: 0.855)           // #DADADA
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
