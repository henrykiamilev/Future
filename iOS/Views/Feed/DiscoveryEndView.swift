import SwiftUI

struct DiscoveryEndView: View {

    var body: some View {
        VStack(spacing: Theme.spacingL) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Theme.textTertiary)

            Text("That's today's picks")
                .font(Theme.titleFont)
                .foregroundColor(Theme.textPrimary)

            Text("Come back tomorrow for more from the community.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingXL)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}
