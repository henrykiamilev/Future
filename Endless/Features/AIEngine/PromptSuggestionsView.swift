import SwiftUI

/// Gentle prompt suggestions that help users articulate their goals.
/// Tapping a suggestion inserts it as a starting point in the text field.
struct PromptSuggestionsView: View {
    @Environment(\.colorScheme) private var colorScheme

    let onSuggestionTapped: (String) -> Void

    private let suggestions = PromptSuggestion.all

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Not sure where to start?")
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.textTertiary(for: colorScheme))

            FlowLayout(spacing: Theme.Spacing.xs) {
                ForEach(suggestions) { suggestion in
                    SuggestionChip(
                        text: suggestion.prompt,
                        onTap: { onSuggestionTapped(suggestion.starterText) }
                    )
                }
            }
        }
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(Theme.Typography.caption1)
                .foregroundColor(Theme.Colors.textSecondary(for: colorScheme))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.backgroundSecondary(for: colorScheme))
                .cornerRadius(Theme.Radius.full)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prompt Suggestion

struct PromptSuggestion: Identifiable {
    let id = UUID()
    let prompt: String
    let starterText: String

    static let all: [PromptSuggestion] = [
        PromptSuggestion(
            prompt: "What do you want to achieve?",
            starterText: "I want to "
        ),
        PromptSuggestion(
            prompt: "What school do you go to?",
            starterText: "I'm currently studying at "
        ),
        PromptSuggestion(
            prompt: "What are you most confident in?",
            starterText: "I'm good at "
        ),
        PromptSuggestion(
            prompt: "What do you struggle with?",
            starterText: "I find it difficult to "
        ),
        PromptSuggestion(
            prompt: "When do you need this done?",
            starterText: "I need to accomplish this by "
        ),
        PromptSuggestion(
            prompt: "How can Endless help?",
            starterText: "I want Endless to help me "
        )
    ]
}

// MARK: - Flow Layout

/// A layout that arranges views in a flowing, wrapping manner.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            ), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

// MARK: - Preview

#Preview("Suggestions - Light") {
    PromptSuggestionsView { text in
        print("Tapped: \(text)")
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Suggestions - Dark") {
    PromptSuggestionsView { text in
        print("Tapped: \(text)")
    }
    .padding()
    .background(Theme.FallbackColors.darkBackground)
    .preferredColorScheme(.dark)
}
