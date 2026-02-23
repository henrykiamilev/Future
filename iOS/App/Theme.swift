import SwiftUI

enum Theme {

    // MARK: - Colors

    static let background = Color(red: 0.976, green: 0.973, blue: 0.965)     // #F9F8F6 warm off-white
    static let surface = Color.white
    static let textPrimary = Color(red: 0.10, green: 0.10, blue: 0.10)       // near-black
    static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.45)     // mid-gray
    static let textTertiary = Color(red: 0.65, green: 0.65, blue: 0.65)      // light gray
    static let accent = Color(red: 0.12, green: 0.12, blue: 0.12)            // almost black
    static let separator = Color(red: 0.90, green: 0.90, blue: 0.88)
    static let likeActive = Color(red: 0.90, green: 0.25, blue: 0.20)        // muted red
    static let destructive = Color.red

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    // MARK: - Corner Radius

    static let radiusS: CGFloat = 4
    static let radiusM: CGFloat = 8
    static let radiusL: CGFloat = 12
    static let radiusXL: CGFloat = 16

    // MARK: - Typography

    static let titleFont: Font = .system(size: 18, weight: .semibold, design: .default)
    static let headlineFont: Font = .system(size: 15, weight: .medium, design: .default)
    static let bodyFont: Font = .system(size: 14, weight: .regular, design: .default)
    static let captionFont: Font = .system(size: 12, weight: .regular, design: .default)
    static let labelFont: Font = .system(size: 11, weight: .medium, design: .default)
    static let statNumberFont: Font = .system(size: 16, weight: .semibold, design: .rounded)
    static let statLabelFont: Font = .system(size: 11, weight: .regular, design: .default)
    static let sectionHeaderFont: Font = .system(size: 12, weight: .semibold, design: .default)

    // MARK: - Shadows

    static let shadowLight = Color.black.opacity(0.04)
}

// MARK: - Profile Themes

enum ProfileTheme: String, CaseIterable, Sendable {
    case `default`
    case midnight
    case ocean
    case sunset
    case forest
    case lavender
    case slate

    var displayName: String {
        switch self {
        case .default:  return "Default"
        case .midnight: return "Midnight"
        case .ocean:    return "Ocean"
        case .sunset:   return "Sunset"
        case .forest:   return "Forest"
        case .lavender: return "Lavender"
        case .slate:    return "Slate"
        }
    }

    var background: Color {
        switch self {
        case .default:  return Theme.background
        case .midnight: return Color(red: 0.08, green: 0.08, blue: 0.12)
        case .ocean:    return Color(red: 0.05, green: 0.12, blue: 0.18)
        case .sunset:   return Color(red: 0.18, green: 0.08, blue: 0.06)
        case .forest:   return Color(red: 0.05, green: 0.14, blue: 0.08)
        case .lavender: return Color(red: 0.14, green: 0.10, blue: 0.18)
        case .slate:    return Color(red: 0.12, green: 0.13, blue: 0.14)
        }
    }

    var textPrimary: Color {
        switch self {
        case .default:  return Theme.textPrimary
        default:        return Color(white: 0.95)
        }
    }

    var textSecondary: Color {
        switch self {
        case .default:  return Theme.textSecondary
        default:        return Color(white: 0.65)
        }
    }

    var accent: Color {
        switch self {
        case .default:  return Theme.accent
        case .midnight: return Color(red: 0.40, green: 0.50, blue: 0.95)
        case .ocean:    return Color(red: 0.20, green: 0.65, blue: 0.85)
        case .sunset:   return Color(red: 0.95, green: 0.55, blue: 0.30)
        case .forest:   return Color(red: 0.30, green: 0.75, blue: 0.45)
        case .lavender: return Color(red: 0.65, green: 0.50, blue: 0.90)
        case .slate:    return Color(red: 0.55, green: 0.60, blue: 0.70)
        }
    }

    var previewColors: [Color] {
        [background, accent, textPrimary]
    }
}
