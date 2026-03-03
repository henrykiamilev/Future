import SwiftUI

struct ShuffleOnboardingOverlay: View {

    let onDismiss: () -> Void

    @State private var currentStep = 0
    @State private var handOffset: CGSize = .zero
    @State private var handOpacity: Double = 1.0

    private let steps: [(icon: String, direction: String, label: String, color: Color)] = [
        ("hand.point.right.fill", "right", "Swipe right to follow", .green),
        ("hand.point.left.fill", "left", "Swipe left to skip", .gray),
        ("hand.point.up.fill", "up", "Swipe up to save for later", .orange),
    ]

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if currentStep >= steps.count - 1 {
                        onDismiss()
                    }
                }

            VStack(spacing: Theme.spacingXL) {
                Spacer()

                // Animated hand
                ZStack {
                    // Hand icon
                    Image(systemName: steps[currentStep].icon)
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(.white)
                        .offset(handOffset)
                        .opacity(handOpacity)
                }
                .frame(height: 100)

                // Instruction text
                VStack(spacing: Theme.spacingS) {
                    Text(steps[currentStep].label)
                        .font(.custom("OpenSauceSans-SemiBold", size: 20))
                        .foregroundColor(.white)

                    // Dots indicator
                    HStack(spacing: 6) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Circle()
                                .fill(i == currentStep ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                }

                // Tap to continue / Get started button
                Button {
                    if currentStep < steps.count - 1 {
                        advanceStep()
                    } else {
                        onDismiss()
                    }
                } label: {
                    Text(currentStep < steps.count - 1 ? "Tap to continue" : "Start shuffling")
                        .font(.custom("OpenSauceSans-Medium", size: 15))
                        .foregroundColor(currentStep < steps.count - 1 ? .white.opacity(0.7) : .black)
                        .padding(.horizontal, Theme.spacingL)
                        .padding(.vertical, Theme.spacingM)
                        .background(
                            currentStep < steps.count - 1
                                ? AnyShapeStyle(Color.white.opacity(0.15))
                                : AnyShapeStyle(Color.white)
                        )
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, Theme.spacingXL)
        }
        .onAppear {
            animateHand()
        }
    }

    private func advanceStep() {
        withAnimation(.easeOut(duration: 0.2)) {
            handOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentStep = min(currentStep + 1, steps.count - 1)
            handOffset = .zero
            withAnimation(.easeIn(duration: 0.2)) {
                handOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                animateHand()
            }
        }
    }

    private func animateHand() {
        let step = steps[currentStep]
        let target: CGSize
        switch step.direction {
        case "right":
            target = CGSize(width: 80, height: 0)
        case "left":
            target = CGSize(width: -80, height: 0)
        case "up":
            target = CGSize(width: 0, height: -80)
        default:
            target = .zero
        }

        // Animate: center → direction → fade → reset → repeat
        withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
            handOffset = target
        }

        // Reset and loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            guard currentStep < steps.count else { return }
            let currentDir = steps[currentStep].direction
            // Only loop if still on same step
            if step.direction == currentDir {
                handOffset = .zero
                animateHand()
            }
        }
    }
}
