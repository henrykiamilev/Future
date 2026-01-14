import SwiftUI

/// AI Goal Intake - the core onboarding moment.
/// Users freely describe their goals, background, and what they want to achieve.
struct AIIntakeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var goalText: String = ""
    @State private var isGenerating: Bool = false
    @State private var showSuggestions: Bool = true

    // For token display (will be populated from actual user data)
    @State private var remainingTokens: Int = 3

    // Minimum character count before allowing submission
    private let minimumCharacters = 50

    var body: some View {
        ZStack {
            if isGenerating {
                AILoadingView()
                    .transition(.opacity)
            } else {
                intakeContent
                    .transition(.opacity)
            }
        }
        .animation(Theme.Animation.standard, value: isGenerating)
    }

    // MARK: - Intake Content

    private var intakeContent: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Instructions
                    instructionsSection

                    // Text input
                    textInputSection

                    // Prompt suggestions (shown when text is empty)
                    if showSuggestions && goalText.isEmpty {
                        PromptSuggestionsView { starterText in
                            goalText = starterText
                            showSuggestions = false
                        }
                        .transition(.opacity)
                    }

                    // Character guidance
                    characterGuidance
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xxxl)
            }

            // Bottom action
            bottomSection
        }
        .background(Theme.Colors.background(for: colorScheme))
        .onTapGesture {
            hideKeyboard()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Tell Endless about yourself")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                Text("The more you share, the better your plan")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
            }

            Spacer()

            // Token indicator
            tokenIndicator
        }
    }

    private var tokenIndicator: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(remainingTokens)")
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.FallbackColors.accent)

            Text(remainingTokens == 1 ? "plan left" : "plans left")
                .font(Theme.Typography.caption2)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Share anything that helps us understand you:")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                bulletPoint("What you want to achieve")
                bulletPoint("Your background and experience")
                bulletPoint("What you're good at and what's hard")
                bulletPoint("When you need to reach your goal")
            }
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Circle()
                .fill(Theme.Colors.textTertiary(for: colorScheme))
                .frame(width: 4, height: 4)
                .padding(.top, 7)

            Text(text)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
        }
    }

    // MARK: - Text Input

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            TextEditor(text: $goalText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
                .overlay(
                    // Placeholder
                    Group {
                        if goalText.isEmpty {
                            Text("I'm a junior at UCLA studying economics. I want to get into a top MBA program in 3 years. I'm good with numbers but struggle with networking and public speaking...")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                                .padding(Theme.Spacing.md)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
                .onChange(of: goalText) { _, _ in
                    if !goalText.isEmpty {
                        showSuggestions = false
                    }
                }
        }
    }

    // MARK: - Character Guidance

    private var characterGuidance: some View {
        HStack {
            let count = goalText.count
            let isEnough = count >= minimumCharacters

            Text("\(count) characters")
                .font(Theme.Typography.caption1)
                .foregroundColor(isEnough
                    ? Theme.Colors.textTertiary(for: colorScheme)
                    : Theme.Colors.textSecondary(for: colorScheme))

            if !isEnough && count > 0 {
                Text("(\(minimumCharacters - count) more for best results)")
                    .font(Theme.Typography.caption1)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            }

            Spacer()
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Divider()
                .background(Theme.Colors.textTertiary(for: colorScheme).opacity(0.3))

            Button {
                generatePlan()
            } label: {
                Text("Generate My Plan")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background(for: colorScheme))
    }

    // MARK: - Validation

    private var canSubmit: Bool {
        goalText.count >= minimumCharacters && remainingTokens > 0
    }

    // MARK: - Actions

    private func generatePlan() {
        hideKeyboard()

        withAnimation(Theme.Animation.standard) {
            isGenerating = true
        }

        // Create the user goal input
        let userInput = UserGoalInput(rawText: goalText)

        // Simulate AI generation (actual implementation in AIService)
        // In production, this calls the backend which talks to Gemini
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(Theme.Animation.standard) {
                isGenerating = false
            }

            // Decrement tokens (actual enforcement on server)
            remainingTokens -= 1

            // Navigate to paywall (per PRD flow: after first plan generation)
            appState.completeOnboarding()
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Preview

#Preview("AI Intake - Light") {
    AIIntakeView()
        .environmentObject(AppState())
        .preferredColorScheme(.light)
}

#Preview("AI Intake - Dark") {
    AIIntakeView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}

#Preview("AI Intake - Loading") {
    AILoadingView()
        .preferredColorScheme(.dark)
}
