//
//  Color+Hex.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import Cocoa

extension String  {
    func conformsTo(_ pattern: String) -> Bool {
        return NSPredicate(format:"SELF MATCHES %@", pattern).evaluate(with: self)
    }
}

extension NSColor {
    convenience init(hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((hex & 0xFF00) >> 8) / 255.0,
            blue: CGFloat((hex & 0xFF)) / 255.0,
            alpha: alpha
        )
    }
    
    convenience init(hex: String, alpha: CGFloat = 1) {
        var cleanedString = hex.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanedString.hasPrefix("#") {
            cleanedString.removeFirst()
        } else if cleanedString.lowercased().hasPrefix("0x") {
            cleanedString.removeFirst(2)
        }

        guard cleanedString.conformsTo("^[a-fA-F0-9]{6}$") else {
            fatalError("Unable to parse color?")
        }

        var value: UInt64 = 0
        guard Scanner(string: cleanedString).scanHexInt64(&value) else {
            fatalError("Unable to parse color?")
        }

        self.init(hex: Int(value), alpha: alpha)
    }
}
