//
//  ContentView.swift
//  ares
//
//  Created by Adrian Hess on 10/10/25.
//

import SwiftUI
import AresKit
import UniformTypeIdentifiers

@_silgen_name("zig_process_file_path")
private func zig_process_file_path(_ path: UnsafePointer<CChar>)

struct ContentView: View {
    @State private var counterValue: Int32 = 0
    @State private var showingFileImporter = false

    var body: some View {
        VStack { // <--- The VStack starts here
            Text("Count: \(counterValue)")
                .font(.largeTitle)
                .padding()

            HStack {
                Button("Decrement") {
                    zig_decrement_counter()
                    updateCounterFromZig()
                }
                .padding()

                Button("Increment") {
                    zig_increment_counter()
                    updateCounterFromZig()
                }
                .padding()
            }
            .padding(.bottom) // Add padding below the HStack for separation

            // NEW: Add the "Select File" button here
            Button("Select File") {
                showingFileImporter = true
            }
            .padding()
        } // <--- The VStack ends here
        .padding()
        .onAppear {
            zig_init_counter()
            updateCounterFromZig()
        }
        .onDisappear {
            zig_deinit_counter()
        }
        // Use the fileImporter modifier for file selection
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.data], // Allow selection of any data type
            allowsMultipleSelection: false // Only allow selecting a single file
        ) { result in
            do {
                if let url = try result.get().first {
                    // Start accessing a security-scoped resource.
                    // This is crucial for accessing files outside the app's sandbox.
                    let didStartAccessing = url.startAccessingSecurityScopedResource()
                    if !didStartAccessing {
                        print("Failed to start accessing security scoped resource for URL: \(url.path)")
                    }

                    // Ensure to stop accessing the resource when done.
                    // This defer will execute when the closure exits.
                    defer {
                        if didStartAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    let filePath = url.path
                    filePath.withCString { cString in
                        zig_process_file_path(cString)
                    }
                    print("Selected file path: \(filePath)")
                }
            } catch {
                print("Error selecting file: \(error.localizedDescription)")
            }
        }
    }

    private func updateCounterFromZig() {
        counterValue = zig_get_counter()
    }
}

#Preview {
    ContentView()
}
