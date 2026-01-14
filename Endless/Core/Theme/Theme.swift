import SwiftUI

// MARK: - Theme

/// Endless design system following Apple-like minimalism.
/// Clean typography, subtle gradients, soft motion, no loud colors.
enum Theme {

    // MARK: - Colors

    enum Colors {
        // Primary backgrounds
        static let backgroundPrimary = Color("BackgroundPrimary")
        static let backgroundSecondary = Color("BackgroundSecondary")
        static let backgroundTertiary = Color("BackgroundTertiary")

        // Text
        static let textPrimary = Color("TextPrimary")
        static let textSecondary = Color("TextSecondary")
        static let textTertiary = Color("TextTertiary")

        // Accent (subtle, calm)
        static let accent = Color("Accent")
        static let accentSubtle = Color("AccentSubtle")

        // Semantic
        static let success = Color("Success")
        static let warning = Color("Warning")
        static let error = Color("Error")

        // Borders and separators
        static let separator = Color("Separator")
        static let border = Color("Border")

        // Calendar event colors (soft, muted palette)
        static let eventBlue = Color("EventBlue")
        static let eventPurple = Color("EventPurple")
        static let eventGreen = Color("EventGreen")
        static let eventOrange = Color("EventOrange")
        static let eventPink = Color("EventPink")
    }

    // MARK: - Fallback Colors (for preview/development)

    enum FallbackColors {
        // Light mode
        static let lightBackground = Color(hex: "FFFFFF")
        static let lightBackgroundSecondary = Color(hex: "F5F5F7")
        static let lightBackgroundTertiary = Color(hex: "E8E8ED")
        static let lightTextPrimary = Color(hex: "1D1D1F")
        static let lightTextSecondary = Color(hex: "6E6E73")
        static let lightTextTertiary = Color(hex: "AEAEB2")

        // Dark mode
        static let darkBackground = Color(hex: "1C1C1E")
        static let darkBackgroundSecondary = Color(hex: "2C2C2E")
        static let darkBackgroundTertiary = Color(hex: "3A3A3C")
        static let darkTextPrimary = Color(hex: "FFFFFF")
        static let darkTextSecondary = Color(hex: "EBEBF5").opacity(0.6)
        static let darkTextTertiary = Color(hex: "EBEBF5").opacity(0.3)

        // Accent
        static let accent = Color(hex: "5E5CE6")
        static let accentSubtle = Color(hex: "5E5CE6").opacity(0.15)

        // Event colors (muted, calm)
        static let eventBlue = Color(hex: "A8C5DA")
        static let eventPurple = Color(hex: "C4B5DC")
        static let eventGreen = Color(hex: "A8D5BA")
        static let eventOrange = Color(hex: "E5C5A5")
        static let eventPink = Color(hex: "E5B5C5")
    }

    // MARK: - Typography

    enum Typography {
        // Large titles
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
        static let title1 = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)

        // Body
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)

        // Small
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption1 = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Corner Radius

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let full: CGFloat = 9999
    }

    // MARK: - Animation

    enum Animation {
        // Soft, purposeful motion (never decorative)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        static let logo = SwiftUI.Animation.easeInOut(duration: 1.5)

        // Spring animations (subtle)
        static let gentle = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let smooth = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.9)
    }

    // MARK: - Shadows

    enum Shadow {
        static let sm = ShadowStyle(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        static let md = ShadowStyle(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        static let lg = ShadowStyle(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Shadow Style

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extension for Shadows

extension View {
    func shadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Adaptive Colors (Light/Dark Mode Support)

extension Theme.Colors {
    /// Returns appropriate background color based on color scheme
    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.FallbackColors.darkBackground : Theme.FallbackColors.lightBackground
    }

    static func backgroundSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.FallbackColors.darkBackgroundSecondary : Theme.FallbackColors.lightBackgroundSecondary
    }

    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.FallbackColors.darkTextPrimary : Theme.FallbackColors.lightTextPrimary
    }

    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Theme.FallbackColors.darkTextSecondary : Theme.FallbackColors.lightTextSecondary
    }
}
