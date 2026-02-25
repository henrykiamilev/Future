import SwiftUI

struct CaughtUpView: View {

    let discoveryRemaining: Int
    let onExplore: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.5))

            Text("You're all caught up")
                .font(.custom("OpenSauceSans-Medium", size: 14))
                .foregroundColor(Theme.textPrimary)

            Text("Come back tomorrow to see what your friends share.")
                .font(.custom("OpenSauceSans-Regular", size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if discoveryRemaining > 0 {
                Button {
                    onExplore()
                } label: {
                    Text("Explore \(discoveryRemaining) new posts")
                        .font(.custom("OpenSauceSans-Regular", size: 12))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}
