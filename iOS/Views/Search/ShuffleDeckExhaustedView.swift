import SwiftUI

struct ShuffleDeckExhaustedView: View {

    let followedCount: Int
    let savedCount: Int

    var body: some View {
        VStack(spacing: Theme.spacingM) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Theme.textTertiary)

            Text("That's your deck for today")
                .font(.custom("OpenSauceSans-Medium", size: 16))
                .foregroundColor(Theme.textPrimary)

            Text("Come back tomorrow for a fresh set of people.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            // Session summary
            if followedCount > 0 || savedCount > 0 {
                HStack(spacing: Theme.spacingL) {
                    if followedCount > 0 {
                        VStack(spacing: 2) {
                            Text("\(followedCount)")
                                .font(Theme.statNumberFont)
                                .foregroundColor(Theme.textPrimary)
                            Text("followed")
                                .font(Theme.labelFont)
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                    if savedCount > 0 {
                        VStack(spacing: 2) {
                            Text("\(savedCount)")
                                .font(Theme.statNumberFont)
                                .foregroundColor(Theme.textPrimary)
                            Text("saved")
                                .font(Theme.labelFont)
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                }
                .padding(.top, Theme.spacingS)
            }
        }
        .padding(.horizontal, Theme.spacingXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
