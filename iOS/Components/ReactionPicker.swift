import SwiftUI

struct ReactionPicker: View {

    let onReact: (String) -> Void
    let onDismiss: () -> Void

    static let emojis = ["🔥", "👏", "😍", "💯", "🤯"]

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            ForEach(Self.emojis, id: \.self) { emoji in
                Button {
                    onReact(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .background(Theme.surface)
        .cornerRadius(Theme.radiusL)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

struct ReactionBar: View {

    let reactions: [ReactionDisplay]
    let onTap: (String) -> Void

    var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: Theme.spacingXS) {
                ForEach(reactions) { reaction in
                    Button {
                        onTap(reaction.emoji)
                    } label: {
                        HStack(spacing: 2) {
                            Text(reaction.emoji)
                                .font(.system(size: 14))
                            if reaction.count > 1 {
                                Text("\(reaction.count)")
                                    .font(Theme.captionFont)
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(reaction.userReacted ? Theme.accent.opacity(0.1) : Theme.background)
                        .cornerRadius(Theme.radiusS)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusS)
                                .stroke(reaction.userReacted ? Theme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ReactionDisplay: Identifiable, Sendable {
    var id: String { emoji }
    let emoji: String
    let count: Int
    let userReacted: Bool
}
