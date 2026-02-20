import SwiftUI

struct SessionReminderView: View {

    let onKeepGoing: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: Theme.spacingL) {
                Image(systemName: "clock")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Theme.textSecondary)

                Text("You've been scrolling for 10 minutes")
                    .font(Theme.titleFont)
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Want to take a break?")
                    .font(Theme.bodyFont)
                    .foregroundColor(Theme.textSecondary)

                VStack(spacing: Theme.spacingM) {
                    Button {
                        onClose()
                    } label: {
                        Text("Close")
                            .font(Theme.headlineFont)
                            .foregroundColor(Theme.surface)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.spacingM)
                            .background(Theme.accent)
                            .cornerRadius(Theme.radiusM)
                    }

                    Button {
                        onKeepGoing()
                    } label: {
                        Text("Keep going")
                            .font(Theme.headlineFont)
                            .foregroundColor(Theme.textTertiary)
                    }
                }
                .padding(.top, Theme.spacingS)
            }
            .padding(Theme.spacingXL)
            .background(Theme.surface)
            .cornerRadius(Theme.radiusXL)
            .shadow(color: Theme.shadowLight, radius: 20, y: 10)
            .padding(.horizontal, Theme.spacingXL)
        }
    }
}
