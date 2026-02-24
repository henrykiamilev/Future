import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// FeedPostCard — Premium Editorial Card
// ═══════════════════════════════════════════════════════════════════════════
//
// Layout:
//   ┌─────────────────────────────────────────────────┐
//   │  PHOTO (aspect-fill, edge-to-edge)              │
//   │                                                   │
//   │                          DISPLAY NAME ──┐ top-R  │
//   │                          caption text   ┘        │
//   │                                                   │
//   ├─────────────────────────────────────────────────┤
//   │  WHITE PANEL (100pt fixed)                       │
//   │                                                   │
//   │  Location text              ┌──────────┐         │
//   │  PLACE LABEL (bold 24pt)    │  React   │         │
//   │                             └──────────┘         │
//   └─────────────────────────────────────────────────┘
//
// ═══════════════════════════════════════════════════════════════════════════

struct FeedPostCard: View {

    let post: FeedPost
    let onReactTapped: () -> Void
    let authorDestination: UUID

    // MARK: - Layout

    private let screenWidth = UIScreen.main.bounds.width
    private let panelHeight: CGFloat = 100

    /// Photo takes the full width, height driven by aspect ratio
    /// Clamped to keep cards tall (portrait feel) — min 1.0 (square), max 1.5
    private var imageAspect: CGFloat {
        guard post.imageWidth > 0, post.imageHeight > 0 else { return 1.25 }
        let raw = CGFloat(post.imageHeight) / CGFloat(post.imageWidth)
        return min(max(raw, 1.0), 1.5)
    }

    private var photoHeight: CGFloat {
        screenWidth * imageAspect
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Photo with overlay ──
            photoSection

            // ── White bottom panel ──
            bottomPanel
        }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        ZStack(alignment: .topTrailing) {
            // Full-bleed image — aspect-fill
            NavigationLink(value: authorDestination) {
                CachedImageView(
                    url: SupabaseConfig.storageURL(for: post.imageURL),
                    targetSize: CGSize(width: screenWidth * 2, height: photoHeight * 2)
                ) {
                    Rectangle()
                        .fill(Color(white: 0.12))
                        .overlay {
                            ProgressView()
                                .tint(.white.opacity(0.3))
                        }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: screenWidth, height: photoHeight)
                .clipped()
            }
            .buttonStyle(.plain)

            // ── Readability gradient at top (subtle, ~12% height) ──
            VStack {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .black.opacity(0.15), location: 0.6),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: photoHeight * 0.18)
                Spacer()
            }
            .allowsHitTesting(false)

            // ── Top-right: name + caption ──
            nameOverlay
                .padding(.trailing, 18)
                .padding(.top, 14)
        }
        .frame(width: screenWidth, height: photoHeight)
    }

    // MARK: - Name Overlay (top-right)

    private var nameOverlay: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Display name — all-caps, visible
            Text(displayName.uppercased())
                .font(.custom("OpenSauceSans-Medium", size: 16))
                .tracking(1.5)
                .foregroundColor(.white)

            // Caption — only if present
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.custom("OpenSauceSans-Regular", size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
    }

    // MARK: - White Bottom Panel

    private var bottomPanel: some View {
        HStack(alignment: .center) {
            // Left — location + bold place label
            VStack(alignment: .leading, spacing: 3) {
                if let location = post.location, !location.isEmpty {
                    Text(location)
                        .font(.custom("OpenSauceSans-Regular", size: 12))
                        .foregroundColor(FeedTokens.textSecondary)
                        .lineLimit(1)
                }

                Text(placeLabel.uppercased())
                    .font(.custom("OpenSauceSans-SemiBold", size: 22))
                    .foregroundColor(FeedTokens.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            // Right — outlined React button
            Button(action: onReactTapped) {
                Text("React")
                    .font(.custom("OpenSauceSans-Medium", size: 14))
                    .foregroundColor(FeedTokens.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(FeedTokens.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: panelHeight)
        .frame(maxWidth: .infinity)
        .background(FeedTokens.panelBackground)
    }

    // MARK: - Helpers

    private var displayName: String {
        if let name = post.displayName, !name.isEmpty { return name }
        return post.username
    }

    /// Extract bold place label from location.
    /// "Evanston, IL" → "EVANSTON"
    /// "Northwestern • Deering Library" → "NORTHWESTERN"
    /// Fallback → display name
    private var placeLabel: String {
        if let location = post.location, !location.isEmpty {
            let separators = CharacterSet(charactersIn: ",·•—–|-/")
            if let first = location.components(separatedBy: separators).first?
                .trimmingCharacters(in: .whitespaces), !first.isEmpty {
                return first
            }
            return location
        }
        return displayName
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feed Design Tokens
// ═══════════════════════════════════════════════════════════════════════════

enum FeedTokens {
    static let panelBackground = Color.white
    static let textPrimary = Color(red: 0.067, green: 0.067, blue: 0.067)       // #111
    static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.45)        // #737373
    static let border = Color(red: 0.855, green: 0.855, blue: 0.855)            // #DADADA
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
