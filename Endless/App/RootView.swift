import SwiftUI

/// Root navigation container that switches between app screens.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background
            Theme.Colors.background(for: colorScheme)
                .ignoresSafeArea()

            // Screen content
            screenContent
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch appState.currentScreen {
        case .launch:
            LaunchView()
                .transition(.opacity)

        case .authentication:
            AuthenticationView()
                .transition(.opacity)

        case .aiIntake:
            AIIntakeView()
                .transition(.opacity)

        case .paywall:
            PaywallView()
                .transition(.opacity)

        case .home:
            CalendarView()
                .transition(.opacity)
        }
    }
}

// MARK: - Placeholder View

/// Temporary placeholder for unimplemented screens.
struct PlaceholderView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(title)
                .font(Theme.Typography.title1)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))

            // Temporary navigation for testing
            if appState.currentScreen == .paywall {
                Button("Continue to Home") {
                    appState.completePaywall()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.Spacing.lg)
            }

            if appState.currentScreen == .home {
                Button("Sign Out") {
                    appState.signOut()
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, Theme.Spacing.lg)
            }
        }
        .padding(Theme.Spacing.lg)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.FallbackColors.accent)
            .cornerRadius(Theme.Radius.md)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundColor(Theme.FallbackColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.FallbackColors.accentSubtle)
            .cornerRadius(Theme.Radius.md)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    RootView()
        .environmentObject(AppState())
}
