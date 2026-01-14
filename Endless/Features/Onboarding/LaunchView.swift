import SwiftUI

/// Launch screen with Endless logo animation.
/// Infinity symbol forms smoothly, establishing calm, premium feel.
struct LaunchView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var animationProgress: CGFloat = 0
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var hasCompletedAnimation = false

    // Animation timing
    private let animationDuration: Double = 1.8
    private let textDelay: Double = 0.8
    private let holdDuration: Double = 0.6

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            // Animated infinity logo
            InfinityLogo(progress: animationProgress)
                .frame(width: 80, height: 40)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                .opacity(logoOpacity)

            // App name
            Text("Endless")
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                .opacity(textOpacity)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background(for: colorScheme))
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Fade in logo
        withAnimation(.easeIn(duration: 0.3)) {
            logoOpacity = 1
        }

        // Animate infinity symbol drawing
        withAnimation(.easeInOut(duration: animationDuration)) {
            animationProgress = 1
        }

        // Fade in text after slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + textDelay) {
            withAnimation(.easeIn(duration: 0.4)) {
                textOpacity = 1
            }
        }

        // Navigate after animation completes
        let totalDuration = animationDuration + holdDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            appState.completelaunch()
        }
    }
}

// MARK: - Infinity Logo Shape

/// Custom infinity symbol that animates its drawing.
struct InfinityLogo: View {
    let progress: CGFloat

    var body: some View {
        InfinityShape()
            .trim(from: 0, to: progress)
            .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }
}

/// Infinity symbol path.
struct InfinityShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width
        let height = rect.height
        let centerY = height / 2

        // Calculate the two circle centers
        let leftCenterX = width * 0.25
        let rightCenterX = width * 0.75
        let radius = min(width * 0.25, height * 0.5) * 0.9

        // Draw infinity using two connected circles
        // Start from the center, go to right loop, back to center, then left loop

        let centerX = width / 2

        // Starting point at center
        path.move(to: CGPoint(x: centerX, y: centerY))

        // Right loop (clockwise)
        path.addCurve(
            to: CGPoint(x: rightCenterX + radius, y: centerY),
            control1: CGPoint(x: centerX + radius * 0.5, y: centerY - radius * 0.8),
            control2: CGPoint(x: rightCenterX + radius * 0.3, y: centerY - radius)
        )

        path.addCurve(
            to: CGPoint(x: centerX, y: centerY),
            control1: CGPoint(x: rightCenterX + radius * 0.3, y: centerY + radius),
            control2: CGPoint(x: centerX + radius * 0.5, y: centerY + radius * 0.8)
        )

        // Left loop (counter-clockwise, continuing the flow)
        path.addCurve(
            to: CGPoint(x: leftCenterX - radius, y: centerY),
            control1: CGPoint(x: centerX - radius * 0.5, y: centerY + radius * 0.8),
            control2: CGPoint(x: leftCenterX - radius * 0.3, y: centerY + radius)
        )

        path.addCurve(
            to: CGPoint(x: centerX, y: centerY),
            control1: CGPoint(x: leftCenterX - radius * 0.3, y: centerY - radius),
            control2: CGPoint(x: centerX - radius * 0.5, y: centerY - radius * 0.8)
        )

        return path
    }
}

// MARK: - Preview

#Preview("Launch - Light") {
    LaunchView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}

#Preview("Launch - Dark") {
    LaunchView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
