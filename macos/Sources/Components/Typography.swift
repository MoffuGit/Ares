//
//  Typography.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/06/26.
//

import SwiftUI

public enum Typography {
    case xs, sm, base, lg, xl
    
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
        }
    }
}

extension View {
    public func typography(_ style: Typography) -> some View {
        self.font(style.font)
    }
}
