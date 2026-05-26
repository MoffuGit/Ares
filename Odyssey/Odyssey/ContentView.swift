//
//  ContentView.swift
//  Odyssey
//
//  Created by Adrian Hess on 26/05/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(hex: "#020202")
                .ignoresSafeArea()
            
            HStack {
                Color(hex: "#080707")
                    .ignoresSafeArea()
                    .clipShape(
                        RoundedRectangle(cornerRadius: 10.0, style: .continuous)
                    ).overlay(
                        RoundedRectangle(cornerRadius: 10.0, style: .continuous)
                            .stroke(Color(hex: "#282828", opacity: 0.5), lineWidth: 1)
                    )
                    .padding( [.horizontal, .bottom], 6)
                    .shadow(color: Color(hex: "#000000", opacity: 0.5),  radius: 6, x: 0, y:3,)
            }
        }
    }
}

#Preview {
    ContentView()
}
