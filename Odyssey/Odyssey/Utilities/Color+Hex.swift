//
//  Color+Hex.swift
//  Odyssey
//

import SwiftUI

extension Color {
    init(hex: String, opacity: Double = 1.0) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch hex.count {
        case 3:
            (red, green, blue) = (
                ((value >> 8) & 0xF) * 17,
                ((value >> 4) & 0xF) * 17,
                (value & 0xF) * 17
            )
        case 6:
            (red, green, blue) = (
                (value >> 16) & 0xFF,
                (value >> 8) & 0xFF,
                value & 0xFF
            )
        default:
            (red, green, blue) = (0, 0, 0)
        }

        self.init(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: opacity
        )
    }
}
