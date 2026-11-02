import SwiftUI
import UIKit

/// Margin's colours. Paper and ink, with the red margin line as the only accent.
/// Every colour has a light and a dark variant and follows the system appearance.
enum Palette {
    static let paper = Color(light: 0xF6F3EC, dark: 0x131315)
    static let ink = Color(light: 0x1C1B1F, dark: 0xECE9E2)
    static let secondaryInk = Color(light: 0x6B6862, dark: 0x9C988F)
    static let ruling = Color(light: 0xD3DCE6, dark: 0x262C35)
    static let marginRed = Color(light: 0xD4513B, dark: 0xE8664F)
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
