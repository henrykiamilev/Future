import SwiftUI

/// One-time journal mode selection screen.
/// User chooses between free-text or guided prompts.
/// This choice is locked once made (stored on user profile).
struct JournalSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var journalService = JournalService.shared

    @State private var selectedMode: JournalMode?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    // Header
                    headerSection

                    // Mode options
                    modeOptionsSection

                    // Info about lock
                    lockInfoSection

                    // Confirm button
                    confirmButton

                    Spacer(minLength: Theme.Spacing.xxl)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)
            }
            .background(Theme.Colors.background(for: colorScheme))
            .navigationTitle("Journal Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.FallbackColors.accent)

            Text("How would you like to journal?")
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                .multilineTextAlignment(.center)

            Text("Choose the style that feels right for you.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Mode Options

    private var modeOptionsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            modeOption(
                mode: .freeText,
                title: "Free Writing",
                description: "Write whatever comes to mind. No prompts, no structure—just your thoughts.",
                icon: "text.alignleft"
            )

            modeOption(
                mode: .guidedPrompts,
                title: "Guided Prompts",
                description: "Receive a gentle question each day to help guide your reflection.",
                icon: "text.bubble"
            )
        }
        .padding(.top, Theme.Spacing.md)
    }

    private func modeOption(mode: JournalMode, title: String, description: String, icon: String) -> some View {
        Button {
            withAnimation(Theme.Animation.quick) {
                selectedMode = mode
            }
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(selectedMode == mode
                        ? Theme.FallbackColors.accent
                        : Theme.Colors.textTertiary(for: colorScheme))
                    .frame(width: 32)

                // Content
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                    Text(description)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Selection indicator
                Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(selectedMode == mode
                        ? Theme.FallbackColors.accent
                        : Theme.Colors.textTertiary(for: colorScheme))
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(
                        selectedMode == mode
                            ? Theme.FallbackColors.accent
                            : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lock Info

    private var lockInfoSection: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            Text("This choice is saved to personalize your experience. You can change it later in Settings if needed.")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                .multilineTextAlignment(.leading)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.backgroundSecondary(for: colorScheme))
        .cornerRadius(Theme.Radius.sm)
    }

    // MARK: - Confirm Button

    private var confirmButton: some View {
        Button {
            confirmSelection()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Continue")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(selectedMode == nil || isLoading)
        .opacity(selectedMode == nil ? 0.6 : 1)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Actions

    private func confirmSelection() {
        guard let mode = selectedMode else { return }

        isLoading = true

        Task {
            do {
                try await journalService.setJournalMode(mode)
                dismiss()
            } catch {
                errorMessage = "Failed to save preference. Please try again."
                isLoading = false
            }
        }
    }
}

// MARK: - Preview

#Preview("Journal Setup") {
    JournalSetupView()
}
