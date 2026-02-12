import SwiftUI

struct SocialLinksRow: View {

    let instagramHandle: String?
    let snapchatHandle: String?

    var body: some View {
        let hasLinks = instagramHandle != nil || snapchatHandle != nil

        if hasLinks {
            HStack(spacing: Theme.spacingS) {
                if let ig = instagramHandle, !ig.isEmpty {
                    SocialLinkButton(platform: .instagram, handle: ig)
                }
                if let snap = snapchatHandle, !snap.isEmpty {
                    SocialLinkButton(platform: .snapchat, handle: snap)
                }
            }
        }
    }
}
