import SwiftUI

/// Subtle loading view shown while AI generates a plan.
/// Calm, reassuring messaging that sets expectations.
struct AILoadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentMessageIndex = 0
    @State private var messageOpacity: Double = 1
    @State private var dotCount = 0

    private let messages = [
        "Understanding your goals",
        "Researching pathways",
        "Building your plan",
        "Almost there"
    ]

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let messageTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // Animated infinity logo
            PulsingInfinityLogo()
                .frame(width: 60, height: 30)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

            // Loading message
            VStack(spacing: Theme.Spacing.sm) {
                Text(messages[currentMessageIndex] + dots)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                    .opacity(messageOpacity)
                    .animation(.easeInOut(duration: 0.3), value: messageOpacity)

                Text("This may take a moment")
                    .font(Theme.Typography.footnote)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background(for: colorScheme))
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 4
        }
        .onReceive(messageTimer) { _ in
            cycleMessage()
        }
    }

    private var dots: String {
        String(repeating: ".", count: dotCount)
    }

    private func cycleMessage() {
        withAnimation(.easeOut(duration: 0.2)) {
            messageOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            currentMessageIndex = (currentMessageIndex + 1) % messages.count
            withAnimation(.easeIn(duration: 0.2)) {
                messageOpacity = 1
            }
        }
    }
}

// MARK: - Pulsing Infinity Logo

struct PulsingInfinityLogo: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        InfinityShape()
            .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.05
                    opacity = 0.7
                }
            }
    }
}

// MARK: - Preview

#Preview("Loading - Light") {
    AILoadingView()
        .preferredColorScheme(.light)
}

#Preview("Loading - Dark") {
    AILoadingView()
        .preferredColorScheme(.dark)
}
