import SwiftUI

/// Sheet for creating or viewing a journal entry.
/// Supports both free-text and guided prompt modes.
struct JournalEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var journalService = JournalService.shared

    let existingEntry: JournalEntry?

    @State private var content: String = ""
    @State private var isEditing: Bool = false
    @State private var isSaving: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var errorMessage: String?

    @FocusState private var isTextEditorFocused: Bool

    private var isNewEntry: Bool {
        existingEntry == nil
    }

    private var currentPrompt: String {
        if let entry = existingEntry, let prompt = entry.promptUsed {
            return prompt
        }
        return journalService.todaysPrompt
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        // Date
                        dateSection

                        // Prompt (for guided mode)
                        if journalService.journalMode == .guidedPrompts {
                            promptSection
                        }

                        // Content
                        contentSection

                        // Word count
                        if !content.isEmpty {
                            wordCountSection
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }

                // Delete button (for existing entries)
                if existingEntry != nil && !isEditing {
                    deleteSection
                }
            }
            .background(Theme.Colors.background(for: colorScheme))
            .navigationTitle(isNewEntry ? "New Entry" : "Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing && !isNewEntry {
                        Button("Cancel") {
                            isEditing = false
                            content = existingEntry?.content ?? ""
                        }
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isNewEntry || isEditing {
                        Button("Save") {
                            saveEntry()
                        }
                        .fontWeight(.semibold)
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    } else {
                        Button("Edit") {
                            isEditing = true
                            isTextEditorFocused = true
                        }
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Delete Entry", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleteEntry()
                }
            } message: {
                Text("Are you sure you want to delete this journal entry? This cannot be undone.")
            }
        }
        .onAppear {
            setupInitialState()
        }
    }

    // MARK: - Date Section

    private var dateSection: some View {
        HStack {
            Image(systemName: "calendar")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            Text(formattedDate)
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            Spacer()
        }
    }

    private var formattedDate: String {
        if let entry = existingEntry {
            if entry.isToday {
                return "Today"
            }
            return entry.formattedDate
        }
        return "Today"
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("TODAY'S PROMPT")
                .font(Theme.Typography.caption2)
                .foregroundColor(Theme.FallbackColors.accent)

            Text(currentPrompt)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.FallbackColors.accentSubtle)
        .cornerRadius(Theme.Radius.md)
    }

    // MARK: - Content Section

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if isNewEntry || isEditing {
                // Editable text editor
                ZStack(alignment: .topLeading) {
                    if content.isEmpty {
                        Text(placeholderText)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }

                    TextEditor(text: $content)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                        .scrollContentBackground(.hidden)
                        .focused($isTextEditorFocused)
                        .frame(minHeight: 200)
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.md)
            } else {
                // Read-only view
                Text(content)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                    .cornerRadius(Theme.Radius.md)
            }
        }
    }

    private var placeholderText: String {
        if journalService.journalMode == .guidedPrompts {
            return "Write your thoughts here..."
        }
        return "What's on your mind?"
    }

    // MARK: - Word Count

    private var wordCountSection: some View {
        HStack {
            Spacer()

            Text("\(wordCount) words")
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))
        }
    }

    private var wordCount: Int {
        content.split(separator: " ").count
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete Entry")
            }
            .font(Theme.Typography.body)
            .foregroundColor(Color(hex: "E55050"))
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.backgroundSecondary(for: colorScheme))
    }

    // MARK: - Setup

    private func setupInitialState() {
        if let entry = existingEntry {
            content = entry.content
            isEditing = false
        } else {
            isEditing = true
            // Focus on new entry after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextEditorFocused = true
            }
        }
    }

    // MARK: - Actions

    private func saveEntry() {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        isSaving = true

        Task {
            do {
                if let entry = existingEntry {
                    // Update existing
                    _ = try await journalService.updateEntry(entry.id, content: trimmedContent)
                } else {
                    // Create new
                    let prompt = journalService.journalMode == .guidedPrompts ? currentPrompt : nil
                    _ = try await journalService.createEntry(content: trimmedContent, prompt: prompt)
                }
                dismiss()
            } catch {
                errorMessage = "Failed to save entry. Please try again."
                isSaving = false
            }
        }
    }

    private func deleteEntry() {
        guard let entry = existingEntry else { return }

        Task {
            do {
                try await journalService.deleteEntry(entry.id)
                dismiss()
            } catch {
                errorMessage = "Failed to delete entry."
            }
        }
    }
}

// MARK: - Preview

#Preview("New Entry") {
    JournalEntrySheet(existingEntry: nil)
}

#Preview("Existing Entry") {
    JournalEntrySheet(
        existingEntry: JournalEntry(
            userId: "user1",
            content: "Today was a productive day. I managed to complete all my planned tasks and even had time for a short walk. Feeling grateful for the progress I'm making.",
            mode: .freeText
        )
    )
}
