import SwiftUI

/// Design tokens for the Apple × Anthropic visual language.
/// Single source of truth — replaces all scattered Color/Font literals.
enum Design {
    // MARK: - Anthropic Brand
    static let terracotta = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757
    static let coral      = Color(red: 0.871, green: 0.533, blue: 0.427) // #DE886D

    // MARK: - Status (system semantic — adapts to accessibility)
    static let statusActive   = Color.green
    static let statusWarning  = Color.orange
    static let statusQuestion = Color.blue
    static let statusError    = Color.red
    static let statusIdle     = Color.secondary

    // MARK: - Borders
    static let border      = Color.white.opacity(0.08)
    static let borderHover = Color.white.opacity(0.18)

    // MARK: - Tool Colors (softer, native-feeling)
    static func toolColor(_ tool: String) -> Color {
        switch tool.lowercased() {
        case "bash":        return .green
        case "edit", "write": return .blue
        case "read":        return .yellow
        case "grep", "glob": return .purple
        case "agent":       return terracotta
        default:            return .secondary
        }
    }

    // MARK: - Typography (SF Pro default, SF Mono for code only)

    static func headline(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func caption(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Spacing (8pt grid)
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24

    // MARK: - Card
    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 12
}
