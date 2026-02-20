import SwiftUI

struct CaughtUpView: View {

    let discoveryRemaining: Int
    let onExplore: () -> Void

    var body: some View {
        VStack(spacing: Theme.spacingL) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.6))

            Text("You're all caught up")
                .font(Theme.titleFont)
                .foregroundColor(Theme.textPrimary)

            Text("Come back tomorrow to see what your friends share.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)

            if discoveryRemaining > 0 {
                Button {
                    onExplore()
                } label: {
                    Text("Explore \(discoveryRemaining) new posts")
                        .font(Theme.captionFont)
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.top, Theme.spacingS)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}
