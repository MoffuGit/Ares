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
            Color(Color(hex: "#f8f8f8"))
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Color(Color(hex: "#f8f8f8"))
                        .frame(maxWidth: 250, maxHeight: .infinity)
                    
                    Color(.windowBackgroundColor)
                        .ignoresSafeArea()
                        .clipShape(
                            RoundedRectangle(cornerRadius: 10.0, style: .continuous)
                        )
                        .padding( [.horizontal], 6)
                }
                
                Color(Color(hex: "#f8f8f8"))
                    .frame(maxWidth: .infinity, maxHeight: 24)
            }
        }
    }
}

#Preview {
    ContentView()
}
