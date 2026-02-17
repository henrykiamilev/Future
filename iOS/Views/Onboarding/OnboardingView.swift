import SwiftUI

struct OnboardingView: View {

    let onFinished: () -> Void

    @State private var currentPage = 0

    private let pages: [(icon: String, title: String, subtitle: String)] = [
        (
            "camera.fill",
            "One Photo a Day",
            "Curated limits you to a single post every 24 hours. Make it count."
        ),
        (
            "star.fill",
            "Build Your Signature",
            "Pin up to 3 of your best posts to your profile permanently."
        ),
        (
            "person.2.fill",
            "Follow & Discover",
            "Find friends, explore the feed, and see what others are sharing today."
        )
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Page content
                VStack(spacing: Theme.spacingXL) {
                    Image(systemName: pages[currentPage].icon)
                        .font(.system(size: 56, weight: .thin))
                        .foregroundColor(Theme.accent)

                    Text(pages[currentPage].title)
                        .font(Theme.titleFont)
                        .foregroundColor(Theme.textPrimary)

                    Text(pages[currentPage].subtitle)
                        .font(Theme.bodyFont)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingXXL)
                }
                .animation(.easeInOut(duration: 0.25), value: currentPage)

                Spacer()

                // Page dots
                HStack(spacing: Theme.spacingS) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Theme.accent : Theme.separator)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, Theme.spacingXL)

                // Button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        onFinished()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .font(Theme.headlineFont)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .cornerRadius(Theme.radiusM)
                }
                .padding(.horizontal, Theme.spacingL)
                .padding(.bottom, Theme.spacingS)

                // Skip
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        onFinished()
                    }
                    .font(Theme.captionFont)
                    .foregroundColor(Theme.textTertiary)
                }

                Spacer()
                    .frame(height: Theme.spacingXL)
            }
        }
    }
}
