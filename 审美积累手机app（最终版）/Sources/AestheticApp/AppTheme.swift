import SwiftUI
import Foundation

/// 设计规范颜色（沿用 Mac 版）
enum AppTheme {
    static let background = Color(hex: 0xF8F5EE)
    static let canvasBackground = Color(hex: 0xF7F2EC)
    static let primaryText = Color(hex: 0x2A3B4E)
    static let primarySoft = Color(hex: 0x4A5B6E)
    static let cardBackground = Color.white
    static let divider = Color(hex: 0xE5E0D5)
    static let secondaryText = Color(hex: 0x8A93A0)
    static let danger = Color(hex: 0xB03A2E)

    /// 圈选可选颜色
    static let regionPalette: [String] = [
        "#2A3B4E", "#B03A2E", "#D97742", "#E0A825",
        "#5B8C5A", "#3A7CA5", "#6C5B9E", "#C25B8A"
    ]
    static let defaultRegionColor = "#2A3B4E"
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        self.init(hex: UInt32(value & 0xFFFFFF))
    }
}
