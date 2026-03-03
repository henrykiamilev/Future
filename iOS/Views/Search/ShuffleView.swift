import SwiftUI

struct ShuffleView: View {

    @ObservedObject var viewModel: ShuffleViewModel

    @State private var dragOffset: CGSize = .zero
    @State private var swipeDirection: SwipeDirection? = nil

    @AppStorage("hasSeenShuffleTutorial") private var hasSeenTutorial = false
    @State private var showTutorial = false

    private let swipeThreshold: CGFloat = 100
    private let verticalSwipeThreshold: CGFloat = 120

    private enum SwipeDirection {
        case left, right, up
    }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            if viewModel.isLoading && viewModel.cards.isEmpty {
                loadingState
            } else if viewModel.isExhausted && viewModel.cards.isEmpty {
                ShuffleDeckExhaustedView(
                    followedCount: viewModel.followedCount,
                    savedCount: viewModel.savedCount
                )
            } else if viewModel.cards.isEmpty {
                emptyState
            } else {
                VStack(spacing: Theme.spacingM) {
                    remainingBadge
                    cardStack
                    Spacer(minLength: 0)
                }
                .padding(.top, Theme.spacingS)
            }

            // First-time tutorial overlay
            if showTutorial {
                ShuffleOnboardingOverlay {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showTutorial = false
                        hasSeenTutorial = true
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .task {
            await viewModel.loadDeck()
            if !hasSeenTutorial && !viewModel.cards.isEmpty {
                withAnimation { showTutorial = true }
            }
        }
    }

    // MARK: - Remaining Badge

    private var remainingBadge: some View {
        HStack(spacing: Theme.spacingXS) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 11, weight: .medium))
            Text("\(viewModel.cards.count) remaining")
                .font(Theme.labelFont)
        }
        .foregroundColor(Theme.textTertiary)
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        ZStack {
            // Background cards (stacked behind)
            ForEach(Array(viewModel.cards.dropFirst().prefix(2).enumerated()), id: \.element.id) { index, card in
                ShuffleCardView(card: card, isTopCard: false, dragOffset: .zero)
                    .scaleEffect(1.0 - CGFloat(index + 1) * 0.04)
                    .offset(y: CGFloat(index + 1) * 8)
                    .opacity(1.0 - CGFloat(index + 1) * 0.15)
                    .allowsHitTesting(false)
            }

            // Top card — interactive with NavigationLink for tap
            if let topCard = viewModel.cards.first {
                NavigationLink(value: topCard.id) {
                    ShuffleCardView(card: topCard, isTopCard: true, dragOffset: dragOffset)
                }
                .buttonStyle(.plain)
                .offset(x: dragOffset.width, y: min(dragOffset.height, 0))
                .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                .overlay(swipeOverlay)
                .simultaneousGesture(dragGesture)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: dragOffset)
            }
        }
        .padding(.horizontal, Theme.spacingL)
        .frame(maxHeight: UIScreen.main.bounds.height * 0.68)
    }

    // MARK: - Swipe Overlay (visual feedback)

    @ViewBuilder
    private var swipeOverlay: some View {
        ZStack {
            // Follow indicator (swipe right)
            if dragOffset.width > 30 {
                let progress = Double(min(dragOffset.width, swipeThreshold)) / Double(swipeThreshold)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.green.opacity(progress * 0.3))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 44, weight: .medium))
                            if dragOffset.width > 50 {
                                Text("FOLLOW")
                                    .font(.custom("OpenSauceSans-Bold", size: 14))
                                    .tracking(2.0)
                            }
                        }
                        .foregroundColor(.green)
                        .opacity(progress)
                    }
                    .allowsHitTesting(false)
            }

            // Skip indicator (swipe left)
            if dragOffset.width < -30 {
                let progress = Double(min(-dragOffset.width, swipeThreshold)) / Double(swipeThreshold)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.gray.opacity(progress * 0.2))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "xmark")
                                .font(.system(size: 44, weight: .medium))
                            if -dragOffset.width > 50 {
                                Text("SKIP")
                                    .font(.custom("OpenSauceSans-Bold", size: 14))
                                    .tracking(2.0)
                            }
                        }
                        .foregroundColor(Theme.textTertiary)
                        .opacity(progress)
                    }
                    .allowsHitTesting(false)
            }

            // Save indicator (swipe up)
            if dragOffset.height < -30 {
                let progress = Double(min(-dragOffset.height, verticalSwipeThreshold)) / Double(verticalSwipeThreshold)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.orange.opacity(progress * 0.25))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 44, weight: .medium))
                            if -dragOffset.height > 50 {
                                Text("SAVE")
                                    .font(.custom("OpenSauceSans-Bold", size: 14))
                                    .tracking(2.0)
                            }
                        }
                        .foregroundColor(.orange)
                        .opacity(progress)
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                // Determine primary swipe direction
                if horizontal > swipeThreshold {
                    // Swipe right -> Follow
                    completeSwipe(direction: .right, action: .followed)
                } else if horizontal < -swipeThreshold {
                    // Swipe left -> Skip
                    completeSwipe(direction: .left, action: .skipped)
                } else if vertical < -verticalSwipeThreshold {
                    // Swipe up -> Save
                    completeSwipe(direction: .up, action: .saved)
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func completeSwipe(direction: SwipeDirection, action: ShuffleAction) {
        let flyAwayOffset: CGSize
        switch direction {
        case .right:
            flyAwayOffset = CGSize(width: 500, height: 0)
        case .left:
            flyAwayOffset = CGSize(width: -500, height: 0)
        case .up:
            flyAwayOffset = CGSize(width: 0, height: -600)
        }

        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = flyAwayOffset
        }

        // After card flies away, reset and remove
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = .zero
            viewModel.swipe(action)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: Theme.spacingM) {
            ProgressView()
                .tint(Theme.textTertiary)
            Text("Building your deck...")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingS) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(Theme.textTertiary)
            Text("No one new right now")
                .font(Theme.headlineFont)
                .foregroundColor(Theme.textPrimary)
            Text("Check back later for more people to discover.")
                .font(Theme.bodyFont)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.spacingXL)
    }
}
