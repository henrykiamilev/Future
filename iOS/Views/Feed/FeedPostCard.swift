import SwiftUI

// ═══════════════════════════════════════════════════════════════════════════
// FeedPostCard — Full-Screen Gallery Card
// ═══════════════════════════════════════════════════════════════════════════
//
// Layout (top → bottom):
//   ┌─────────────────────────────────────────────────┐
//   │  PHOTO (aspect-fill, edge-to-edge, ~85-90%)     │
//   │                                                   │
//   │  ┌────────── top-right overlay ──────────┐       │
//   │  │  DISPLAY NAME (all-caps, medium, 14pt)│       │
//   │  │  caption (sentence case, 13pt)        │       │
//   │  └───────────────────────────────────────┘       │
//   │                                                   │
//   ├─────────────────────────────────────────────────┤
//   │  WHITE PANEL (~10-15% height)                    │
//   │  ┌───────────────────────────────┐  ┌────────┐  │
//   │  │ Location · timestamp          │  │ React  │  │
//   │  │ PLACE LABEL (bold, 24pt)      │  └────────┘  │
//   │  └───────────────────────────────┘               │
//   └─────────────────────────────────────────────────┘
//
// ═══════════════════════════════════════════════════════════════════════════

struct FeedPostCard: View {

    let post: FeedPost
    let onReactTapped: () -> Void
    let onProfileTapped: () -> Void
    let cardHeight: CGFloat
    let chromeVisible: Bool

    // MARK: - Layout Constants

    private let screenWidth = UIScreen.main.bounds.width

    /// White bottom panel height — ~12% of card
    private var panelHeight: CGFloat {
        max(90, cardHeight * 0.12)
    }

    /// Photo region height — everything above the white panel
    private var photoHeight: CGFloat {
        cardHeight - panelHeight
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Photo region (aspect-fill, full-bleed) ──
            photoRegion
                .frame(width: screenWidth, height: photoHeight)
                .clipped()

            // ── White bottom panel ──
            bottomPanel
                .frame(width: screenWidth, height: panelHeight)
        }
        .frame(width: screenWidth, height: cardHeight)
        .background(FeedTokens.panelBackground)
    }

    // MARK: - Photo Region

    private var photoRegion: some View {
        ZStack(alignment: .topTrailing) {
            // Background image — aspect-fill with center crop
            CachedImageView(
                url: SupabaseConfig.storageURL(for: post.imageURL),
                targetSize: CGSize(width: screenWidth * 2, height: photoHeight * 2)
            ) {
                // Loading placeholder — dominant-color tinted skeleton
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

            // ── Top-right text overlay (name + caption) ──
            if chromeVisible {
                topRightOverlay
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Top-Right Overlay (Name + Caption)

    private var topRightOverlay: some View {
        VStack(alignment: .trailing, spacing: 3) {
            // Display name — all-caps, medium weight, tight tracking
            Text(displayName.uppercased())
                .font(.custom("OpenSauceSans-Medium", size: 14))
                .tracking(1.2)
                .foregroundColor(.white)

            // Caption — sentence case, regular weight (only if present)
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.custom("OpenSauceSans-Regular", size: 13))
                    .foregroundColor(.white.opacity(0.88))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)
        // Subtle scrim behind text for readability
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial.opacity(0.3))
        )
        .padding(.trailing, 18)
        .padding(.top, 12)
        // Tappable — navigates to profile
        .onTapGesture { onProfileTapped() }
    }

    // MARK: - White Bottom Panel

    private var bottomPanel: some View {
        HStack(alignment: .bottom) {
            // Left side — location + place label
            VStack(alignment: .leading, spacing: 4) {
                // Location line (small) + timestamp
                if let location = post.location, !location.isEmpty {
                    Text(location)
                        .font(.custom("OpenSauceSans-Regular", size: 12))
                        .foregroundColor(FeedTokens.textSecondary)
                        .lineLimit(1)
                }

                // Bold place label — the primary location word
                Text(placeLabel.uppercased())
                    .font(.custom("OpenSauceSans-SemiBold", size: 24))
                    .foregroundColor(FeedTokens.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer()

            // Right side — single outlined button
            Button(action: onReactTapped) {
                Text("React")
                    .font(.custom("OpenSauceSans-Medium", size: 14))
                    .foregroundColor(FeedTokens.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(FeedTokens.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(FeedTokens.panelBackground)
        .opacity(chromeVisible ? 1 : 0)
    }

    // MARK: - Helpers

    private var displayName: String {
        if let name = post.displayName, !name.isEmpty {
            return name
        }
        return post.username
    }

    /// Extract a bold "place label" from the location string.
    /// If location is "Evanston, IL" → "EVANSTON"
    /// If location is "Northwestern • Deering Library" → "NORTHWESTERN"
    /// Fallback: display name
    private var placeLabel: String {
        if let location = post.location, !location.isEmpty {
            // Take first component before comma, bullet, dash, or pipe
            let separators = CharacterSet(charactersIn: ",·•—–|-/")
            let first = location.components(separatedBy: separators).first?
                .trimmingCharacters(in: .whitespaces) ?? location
            return first
        }
        // Fallback: use display name as the bold label
        return displayName
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Feed Design Tokens — isolated for this screen
// ═══════════════════════════════════════════════════════════════════════════

enum FeedTokens {
    // Colors
    static let panelBackground = Color.white
    static let textPrimary = Color(hex: 0x111111)
    static let textSecondary = Color(hex: 0x737373)
    static let border = Color(hex: 0xDADADA)
}

// MARK: - Color Hex Extension

private extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex         & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: alpha)
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
