//
//  Typography.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/06/26.
//

import SwiftUI

public enum Typography {
    case xs, sm, base, lg, xl, `2xl`,`3xl`,`4xl`,`5xl`
    
    public var font: Font {
        switch self {
        case .xs:
            return .system(size: 12)
        case .sm:
            return .system(size: 14)
        case .base:
            return .system(size: 16)
        case .lg:
            return .system(size: 18)
        case .xl:
            return .system(size: 20)
        case .`2xl`:
            return .system(size: 24)
        case .`3xl`:
            return .system(size: 30)
        case .`4xl`:
            return .system(size: 36)
        case .`5xl`:
            return .system(size: 48)
        }
    }
}

extension View {
    public func typography(_ style: Typography) -> some View {
        self.font(style.font)
    }
}
