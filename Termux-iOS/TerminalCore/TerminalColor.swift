//
//  TerminalColor.swift
//  Termux-iOS
//
//  ANSI and Xterm-256 Color Palette mapping for SwiftUI/UIKit rendering.
//

import SwiftUI
import UIKit

public struct TerminalColor {
    public static func color(forIndex index: Int, theme: TermuxTheme) -> Color {
        guard index >= 0 && index < 256 else {
            return Color(hex: theme.foregroundHex)
        }
        
        // Standard 16 ANSI colors from user theme
        if index < 16 && index < theme.ansiColorsHex.count {
            return Color(hex: theme.ansiColorsHex[index])
        }
        
        // 16..231: 6x6x6 color cube
        if index >= 16 && index <= 231 {
            let idx = index - 16
            let r = (idx / 36) % 6
            let g = (idx / 6) % 6
            let b = idx % 6
            let rVal = Double(r == 0 ? 0 : 55 + r * 40) / 255.0
            let gVal = Double(g == 0 ? 0 : 55 + g * 40) / 255.0
            let bVal = Double(b == 0 ? 0 : 55 + b * 40) / 255.0
            return Color(red: rVal, green: gVal, blue: bVal)
        }
        
        // 232..255: grayscale ramp
        if index >= 232 && index <= 255 {
            let gray = Double(8 + (index - 232) * 10) / 255.0
            return Color(red: gray, green: gray, blue: gray)
        }
        
        return Color(hex: theme.foregroundHex)
    }
}

extension Color {
    public init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red = Double((rgb & 0xFF0000) >> 16) / 255.0
        let green = Double((rgb & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

extension UIColor {
    public convenience init(hexString: String) {
        var hexSanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
