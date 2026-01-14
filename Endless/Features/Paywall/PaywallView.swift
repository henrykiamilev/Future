import SwiftUI

/// Paywall screen shown after first AI plan generation.
/// Two-column comparison of Free vs Pro with calm, confident messaging.
struct PaywallView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var subscriptionService = SubscriptionService.shared

    @State private var selectedPlan: PricingPlan = .yearly
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                // Header
                headerSection

                // Plan comparison
                planComparisonSection

                // Pricing options
                pricingSection

                // Subscribe button
                subscribeButton

                // Skip option
                skipButton

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xl)
        }
        .background(Theme.Colors.background(for: colorScheme))
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Your plan is ready")
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

            Text("Unlock the full potential of Endless")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Plan Comparison

    private var planComparisonSection: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            // Free column
            planColumn(
                title: "Free",
                features: [
                    "3 AI plans (lifetime)",
                    "View generated plans",
                    "Manual event creation",
                    "Basic calendar features"
                ],
                isHighlighted: false
            )

            // Pro column
            planColumn(
                title: "Pro",
                features: [
                    "52 AI plans per year",
                    "Weekly plan adjustments",
                    "Adaptive scheduling",
                    "Deeper AI guidance",
                    "Priority support"
                ],
                isHighlighted: true
            )
        }
        .padding(.top, Theme.Spacing.md)
    }

    private func planColumn(title: String, features: [String], isHighlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Title
            Text(title)
                .font(Theme.Typography.title3)
                .foregroundColor(isHighlighted
                    ? Theme.FallbackColors.accent
                    : Theme.Colors.textPrimary(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Features
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(features, id: \.self) { feature in
                    featureRow(text: feature, isHighlighted: isHighlighted)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(isHighlighted
                    ? Theme.FallbackColors.accentSubtle
                    : Theme.Colors.backgroundSecondary(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isHighlighted
                    ? Theme.FallbackColors.accent.opacity(0.3)
                    : Color.clear, lineWidth: 1)
        )
    }

    private func featureRow(text: String, isHighlighted: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isHighlighted
                    ? Theme.FallbackColors.accent
                    : Theme.Colors.textTertiary(for: colorScheme))
                .padding(.top, 2)

            Text(text)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            // Yearly option
            pricingOption(
                plan: .yearly,
                title: "Yearly",
                price: "$100",
                subtitle: "per year",
                badge: "Save $20"
            )

            // Monthly option
            pricingOption(
                plan: .monthly,
                title: "Monthly",
                price: "$9.99",
                subtitle: "per month",
                badge: nil
            )
        }
        .padding(.top, Theme.Spacing.md)
    }

    private func pricingOption(
        plan: PricingPlan,
        title: String,
        price: String,
        subtitle: String,
        badge: String?
    ) -> some View {
        Button {
            withAnimation(Theme.Animation.quick) {
                selectedPlan = plan
            }
        } label: {
            HStack {
                // Selection indicator
                Circle()
                    .strokeBorder(
                        selectedPlan == plan
                            ? Theme.FallbackColors.accent
                            : Theme.Colors.textTertiary(for: colorScheme),
                        lineWidth: 2
                    )
                    .background(
                        Circle()
                            .fill(selectedPlan == plan
                                ? Theme.FallbackColors.accent
                                : Color.clear)
                            .padding(4)
                    )
                    .frame(width: 24, height: 24)

                // Title
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                // Badge
                if let badge = badge {
                    Text(badge)
                        .font(Theme.Typography.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Theme.FallbackColors.accent)
                        .cornerRadius(Theme.Radius.xs)
                }

                Spacer()

                // Price
                VStack(alignment: .trailing, spacing: 0) {
                    Text(price)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                    Text(subtitle)
                        .font(Theme.Typography.caption2)
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Colors.backgroundSecondary(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(
                        selectedPlan == plan
                            ? Theme.FallbackColors.accent
                            : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        Button {
            startCheckout()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Continue with Pro")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Skip Button

    private var skipButton: some View {
        Button {
            appState.completePaywall()
        } label: {
            Text("Continue with Free")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Actions

    private func startCheckout() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let priceType: PriceType = selectedPlan == .yearly ? .yearly : .monthly
                try await subscriptionService.startCheckout(priceType: priceType)

                // Note: User will be redirected to Safari for Stripe Checkout
                // When they return, we'll check subscription status
                isLoading = false

                // After checkout opens, navigate to home
                // The webhook will update their subscription status
                appState.completePaywall()
            } catch {
                isLoading = false
                errorMessage = "Unable to start checkout. Please try again."
                print("[PaywallView] Checkout error: \(error)")
            }
        }
    }
}

// MARK: - Pricing Plan

enum PricingPlan {
    case monthly
    case yearly
}

// MARK: - Preview

#Preview("Paywall - Light") {
    PaywallView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}

#Preview("Paywall - Dark") {
    PaywallView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
