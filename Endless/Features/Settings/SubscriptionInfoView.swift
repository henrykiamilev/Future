import SwiftUI

/// View showing subscription details and management options.
struct SubscriptionInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var userService = UserService.shared
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var aiService = AIService.shared

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private var isPro: Bool {
        userService.isPro
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Current plan card
                    currentPlanCard

                    // Token usage
                    tokenUsageSection

                    // Actions
                    actionsSection

                    Spacer(minLength: Theme.Spacing.xxl)
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background(for: colorScheme))
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Current Plan Card

    private var currentPlanCard: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Plan name and badge
            VStack(spacing: Theme.Spacing.sm) {
                Text(isPro ? "Pro" : "Free")
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                Text(isPro ? "Full access to Endless" : "Basic access")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
            }

            // Expiration (Pro only)
            if isPro, let expiresAt = userService.currentProfile?.subscriptionExpiresAt {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))

                    Text("Renews \(formattedDate(expiresAt))")
                        .font(Theme.Typography.caption1)
                }
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            }

            // Features list
            featuresGrid
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            isPro
                ? Theme.FallbackColors.accentSubtle
                : Theme.Colors.backgroundSecondary(for: colorScheme)
        )
        .cornerRadius(Theme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(
                    isPro ? Theme.FallbackColors.accent.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private var featuresGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if isPro {
                featureRow(icon: "checkmark", text: "52 AI plans per year", isIncluded: true)
                featureRow(icon: "checkmark", text: "Weekly plan adjustments", isIncluded: true)
                featureRow(icon: "checkmark", text: "Adaptive scheduling", isIncluded: true)
                featureRow(icon: "checkmark", text: "Deeper AI guidance", isIncluded: true)
            } else {
                featureRow(icon: "checkmark", text: "3 AI plans (lifetime)", isIncluded: true)
                featureRow(icon: "checkmark", text: "View generated plans", isIncluded: true)
                featureRow(icon: "checkmark", text: "Manual event creation", isIncluded: true)
                featureRow(icon: "xmark", text: "Weekly plan adjustments", isIncluded: false)
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func featureRow(icon: String, text: String, isIncluded: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isIncluded
                    ? Theme.FallbackColors.accent
                    : Theme.Colors.textTertiary(for: colorScheme))
                .frame(width: 16)

            Text(text)
                .font(Theme.Typography.caption1)
                .foregroundColor(isIncluded
                    ? Theme.Colors.textPrimary(for: colorScheme)
                    : Theme.Colors.textTertiary(for: colorScheme))
        }
    }

    // MARK: - Token Usage

    private var tokenUsageSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("AI USAGE")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(aiService.remainingTokens)")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.FallbackColors.accent)

                    Text(isPro ? "plans remaining this year" : "plans remaining (lifetime)")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                }

                Spacer()

                // Usage indicator
                CircularProgressView(
                    progress: tokenProgress,
                    lineWidth: 4
                )
                .frame(width: 44, height: 44)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
        }
    }

    private var tokenProgress: Double {
        let total = isPro ? 52 : 3
        let remaining = aiService.remainingTokens
        return Double(remaining) / Double(total)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            if isPro {
                // Manage subscription
                Button {
                    openCustomerPortal()
                } label: {
                    HStack {
                        Text("Manage Subscription")
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .tint(Theme.FallbackColors.accent)
                        } else {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14))
                        }
                    }
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.FallbackColors.accent)
                    .padding(Theme.Spacing.md)
                    .background(Theme.FallbackColors.accentSubtle)
                    .cornerRadius(Theme.Radius.md)
                }
                .disabled(isLoading)

                Text("Manage billing, update payment method, or cancel")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            } else {
                // Upgrade prompt
                Button {
                    startUpgrade()
                } label: {
                    Text("Upgrade to Pro")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isLoading)

                Text("Unlock 52 AI plans per year and adaptive scheduling")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func openCustomerPortal() {
        isLoading = true

        Task {
            do {
                try await subscriptionService.openCustomerPortal()
                isLoading = false
            } catch {
                errorMessage = "Unable to open subscription management"
                isLoading = false
            }
        }
    }

    private func startUpgrade() {
        isLoading = true

        Task {
            do {
                try await subscriptionService.startCheckout(priceType: .yearly)
                isLoading = false
            } catch {
                errorMessage = "Unable to start upgrade"
                isLoading = false
            }
        }
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Theme.FallbackColors.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
        }
    }
}

// MARK: - Preview

#Preview("Subscription Info - Free") {
    SubscriptionInfoView()
}

#Preview("Subscription Info - Pro") {
    SubscriptionInfoView()
}
