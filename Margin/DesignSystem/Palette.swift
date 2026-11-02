import SwiftUI
import UIKit

/// Margin's colours. Paper and ink, with the red margin line as the only accent.
/// Every colour has a light and a dark variant and follows the system appearance.
enum Palette {
    static let paper = Color(light: 0xF6F3EC, dark: 0x131315)
    /// Surface for grouped rows, one step lifted from the paper.
    static let sheet = Color(light: 0xFFFDF8, dark: 0x1D1D20)
    static let ink = Color(light: 0x1C1B1F, dark: 0xECE9E2)
    static let secondaryInk = Color(light: 0x6B6862, dark: 0x9C988F)
    static let faintInk = Color(light: 0xA9A59D, dark: 0x5E5B55)
    static let ruling = Color(light: 0xD3DCE6, dark: 0x262C35)
    static let marginRed = Color(light: 0xD4513B, dark: 0xE8664F)
}

/// The colours a subject can have. Muted so a full timetable doesn't look like a rainbow.
enum SubjectColor: String, CaseIterable, Identifiable, Codable {
    case red, coral, orange, mustard, olive, green, teal, blue, indigo, violet, pink, brown, gray

    var id: String { rawValue }

    var name: String {
        switch self {
        case .red: "Rot"
        case .coral: "Koralle"
        case .orange: "Orange"
        case .mustard: "Senf"
        case .olive: "Oliv"
        case .green: "Grün"
        case .teal: "Petrol"
        case .blue: "Blau"
        case .indigo: "Indigo"
        case .violet: "Violett"
        case .pink: "Rosa"
        case .brown: "Braun"
        case .gray: "Grau"
        }
    }

    var color: Color {
        switch self {
        case .red: Color(light: 0xC2463A, dark: 0xE0675A)
        case .coral: Color(light: 0xDE7A5F, dark: 0xEB8D73)
        case .orange: Color(light: 0xD98A2B, dark: 0xEBA048)
        case .mustard: Color(light: 0xC09A1E, dark: 0xD9B43C)
        case .olive: Color(light: 0x7F8F45, dark: 0x9DAE5E)
        case .green: Color(light: 0x3F8F5E, dark: 0x5BB07B)
        case .teal: Color(light: 0x2F8487, dark: 0x4BA5A8)
        case .blue: Color(light: 0x3672B9, dark: 0x5B93D6)
        case .indigo: Color(light: 0x5260AE, dark: 0x7683CC)
        case .violet: Color(light: 0x8460AB, dark: 0xA283C6)
        case .pink: Color(light: 0xBD5F8E, dark: 0xD67FA9)
        case .brown: Color(light: 0x8E6248, dark: 0xB08166)
        case .gray: Color(light: 0x737A84, dark: 0x959CA6)
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
