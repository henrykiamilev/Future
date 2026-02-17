import SwiftUI

struct SocialLinkButton: View {

    enum Platform {
        case instagram
        case snapchat

        var icon: String {
            switch self {
            case .instagram: return "camera.fill"
            case .snapchat: return "message.fill"
            }
        }

        var label: String {
            switch self {
            case .instagram: return "Instagram"
            case .snapchat: return "Snapchat"
            }
        }
    }

    let platform: Platform
    let handle: String

    var body: some View {
        Button {
            switch platform {
            case .instagram:
                DeepLinkHandler.openInstagram(handle: handle)
            case .snapchat:
                DeepLinkHandler.openSnapchat(handle: handle)
            }
        } label: {
            HStack(spacing: Theme.spacingXS) {
                Image(systemName: platform.icon)
                    .font(.system(size: 12, weight: .medium))

                Text("@\(handle)")
                    .font(Theme.captionFont)
            }
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, Theme.spacingS + 2)
            .padding(.vertical, Theme.spacingXS + 1)
            .background(Theme.background)
            .cornerRadius(Theme.radiusS)
        }
        .buttonStyle(.plain)
    }
}
