import SwiftUI

struct DiscoveryEndView: View {

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Theme.textTertiary)

            Text("That's today's picks")
                .font(.custom("OpenSauceSans-Medium", size: 14))
                .foregroundColor(Theme.textPrimary)

            Text("Come back tomorrow for more from the community.")
                .font(.custom("OpenSauceSans-Regular", size: 12))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }
}
