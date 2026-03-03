import SwiftUI

enum Theme {

    // MARK: - Adaptive Colors (Light / Dark)

    static let background = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)   // #121212
            : UIColor(red: 0.961, green: 0.961, blue: 0.953, alpha: 1) // #F5F5F3
    })

    static let surface = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)   // #1C1C1E
            : UIColor(red: 0.961, green: 0.961, blue: 0.953, alpha: 1)
    })

    static let cardBackground = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1)   // #262628
            : UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)      // white
    })

    static let textPrimary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
            : UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
    })

    static let textSecondary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1)
            : UIColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
    })

    static let textTertiary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
            : UIColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1)
    })

    static let accent = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1)   // near-white
            : UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)   // near-black
    })

    static let separator = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1)
            : UIColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1)
    })

    static let likeActive = Color(red: 0.90, green: 0.25, blue: 0.20)   // muted red (same both modes)
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

    // MARK: - Typography (Open Sauce Sans)

    static let titleFont: Font = .custom("OpenSauceSans-SemiBold", size: 18)
    static let headlineFont: Font = .custom("OpenSauceSans-Medium", size: 15)
    static let bodyFont: Font = .custom("OpenSauceSans-Regular", size: 14)
    static let captionFont: Font = .custom("OpenSauceSans-Regular", size: 12)
    static let labelFont: Font = .custom("OpenSauceSans-Medium", size: 11)
    static let statNumberFont: Font = .custom("OpenSauceSans-SemiBold", size: 16)
    static let statLabelFont: Font = .custom("OpenSauceSans-Regular", size: 11)
    static let sectionHeaderFont: Font = .custom("OpenSauceSans-SemiBold", size: 12)
    static let greetingFont: Font = .custom("OpenSauceSans-Light", size: 28)

    // MARK: - Shadows

    static let shadowLight = Color.black.opacity(0.04)
}

// MARK: - Appearance Preference

enum AppAppearance: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - Profile Theme

enum ProfileTheme: String, CaseIterable, Identifiable {
    case `default`
    case midnight
    case ocean
    case sunset
    case forest
    case lavender
    case slate

    var id: String { rawValue }

    var displayColor: Color {
        switch self {
        case .default:  return Color(red: 0.961, green: 0.961, blue: 0.953)
        case .midnight: return Color(red: 0.10, green: 0.10, blue: 0.18)
        case .ocean:    return Color(red: 0.15, green: 0.35, blue: 0.55)
        case .sunset:   return Color(red: 0.85, green: 0.45, blue: 0.30)
        case .forest:   return Color(red: 0.20, green: 0.40, blue: 0.25)
        case .lavender: return Color(red: 0.60, green: 0.50, blue: 0.70)
        case .slate:    return Color(red: 0.40, green: 0.42, blue: 0.45)
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

// MARK: - Session Duration

enum SessionDuration: String, CaseIterable, Identifiable {
    case five = "5m"
    case ten = "10m"
    case fifteen = "15m"
    case twenty = "20m"
    case thirty = "30m"
    case off = "Off"

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .five: return 300
        case .ten: return 600
        case .fifteen: return 900
        case .twenty: return 1200
        case .thirty: return 1800
        case .off: return nil
        }
    }
}
