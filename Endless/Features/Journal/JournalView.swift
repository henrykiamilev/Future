import SwiftUI

/// Main journal view showing entries and streak progress.
/// Calm, reflective design with no judgment or pressure.
struct JournalView: View {
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var journalService = JournalService.shared

    @State private var showSetup: Bool = false
    @State private var showNewEntry: Bool = false
    @State private var selectedEntry: JournalEntry?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            if journalService.hasSelectedMode {
                // Content
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Streak card
                        streakCard

                        // Today's entry or prompt
                        todaySection

                        // Past entries
                        if !journalService.entries.isEmpty {
                            pastEntriesSection
                        }

                        Spacer(minLength: Theme.Spacing.xxxl)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                }
            } else {
                // Setup prompt
                setupPromptView
            }
        }
        .background(Theme.Colors.background(for: colorScheme))
        .task {
            await journalService.refreshMode()
            if journalService.hasSelectedMode {
                try? await journalService.fetchEntries()
            }
        }
        .sheet(isPresented: $showSetup) {
            JournalSetupView()
        }
        .sheet(isPresented: $showNewEntry) {
            JournalEntrySheet(existingEntry: nil)
        }
        .sheet(item: $selectedEntry) { entry in
            JournalEntrySheet(existingEntry: entry)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Journal")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                Text("A space for reflection")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
            }

            Spacer()

            // New entry button (only if mode is selected)
            if journalService.hasSelectedMode {
                Button {
                    showNewEntry = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.FallbackColors.accent)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Setup Prompt

    private var setupPromptView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

                Text("Begin Your Journal")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

                Text("Choose how you'd like to reflect.\nThis choice helps personalize your experience.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Button {
                showSetup = true
            } label: {
                Text("Get Started")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.Spacing.xl)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Encouragement message
            Text(journalService.streakData.encouragementMessage)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))

            // Stats row
            HStack(spacing: Theme.Spacing.xl) {
                statItem(
                    value: "\(journalService.streakData.currentStreak)",
                    label: "Day streak"
                )

                statItem(
                    value: "\(journalService.streakData.entriesThisMonth)",
                    label: "This month"
                )

                statItem(
                    value: "\(journalService.streakData.totalEntries)",
                    label: "Total"
                )
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.backgroundSecondary(for: colorScheme))
        .cornerRadius(Theme.Radius.lg)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.FallbackColors.accent)

            Text(label)
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
        }
    }

    // MARK: - Today Section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TODAY")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            if let todayEntry = journalService.entry(for: Date()) {
                // Show today's entry
                entryCard(todayEntry, isToday: true)
            } else {
                // Show prompt to write
                todayPromptCard
            }
        }
    }

    private var todayPromptCard: some View {
        Button {
            showNewEntry = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if journalService.journalMode == .guidedPrompts {
                    Text(journalService.todaysPrompt)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                        .multilineTextAlignment(.leading)
                } else {
                    Text("What's on your mind?")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                }

                HStack {
                    Text("Tap to write")
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.FallbackColors.accent)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.FallbackColors.accent)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.FallbackColors.accentSubtle)
            .cornerRadius(Theme.Radius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Past Entries

    private var pastEntriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("PAST ENTRIES")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            ForEach(pastEntries) { entry in
                entryCard(entry, isToday: false)
            }
        }
    }

    private var pastEntries: [JournalEntry] {
        journalService.entries.filter { !$0.isToday }
    }

    private func entryCard(_ entry: JournalEntry, isToday: Bool) -> some View {
        Button {
            selectedEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Date
                HStack {
                    Text(isToday ? "Today" : entry.formattedDate)
                        .font(Theme.Typography.caption1)
                        .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

                    Spacer()

                    if entry.mode == .guidedPrompts {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                    }
                }

                // Content preview
                Text(entry.content)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Word count
                Text("\(entry.wordCount) words")
                    .font(Theme.Typography.caption2)
                    .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.backgroundSecondary(for: colorScheme))
            .cornerRadius(Theme.Radius.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Journal - Light") {
    JournalView()
        .preferredColorScheme(.light)
}

#Preview("Journal - Dark") {
    JournalView()
        .preferredColorScheme(.dark)
}
