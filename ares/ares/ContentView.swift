//
//  ContentView.swift
//  ares
//
//  Created by Adrian Hess on 10/10/25.
//

import SwiftUI
import AresKit

struct ContentView: View {
    // @State property to hold the counter value from Zig.
    // When this changes, SwiftUI will re-render the view.
    @State private var counterValue: Int32 = 0

    var body: some View {
        VStack {
            Text("Count: \(counterValue)")
                .font(.largeTitle)
                .padding()

            HStack {
                Button("Decrement") {
                    zig_decrement_counter() // Call Zig function
                    updateCounterFromZig() // Get updated value
                }
                .padding()

                Button("Increment") {
                    zig_increment_counter() // Call Zig function
                    updateCounterFromZig() // Get updated value
                }
                .padding()
            }
        }
        .padding()
        .onAppear {
            // Initialize the Zig counter and get its initial value when the view appears
            zig_init_counter()
            updateCounterFromZig()
        }
        .onDisappear {
            // Deinitialize the Zig counter when the view disappears
            zig_deinit_counter()
        }
    }

    private func updateCounterFromZig() {
        // Call Zig function to get the latest counter value
        counterValue = zig_get_counter()
    }
}

#Preview {
    ContentView()
}
