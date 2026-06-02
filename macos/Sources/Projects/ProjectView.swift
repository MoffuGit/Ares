//
//  Project.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.
//

import Foundation
import AppKit
import SwiftUI

struct Project: Identifiable {
    let id: String
    var abs_path: String
    var name: String

    init(abs_path: String) {
        self.abs_path = abs_path
        self.id = abs_path
        self.name = URL(fileURLWithPath: abs_path).lastPathComponent
    }
}

struct ProjectsView: View {
    @ObservedObject var app: AppDelegate
    @State private var projects: [Project] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if projects.isEmpty {
                Spacer()
                VStack {
                    Button("Open Existing Project", systemImage: "folder.badge.plus", action: addProject)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(projects) { project in
                    VStack(alignment: .leading) {
                        Text(project.name)
                            .font(.title2)
                            .fontWeight(.medium)

                        Text(project.abs_path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.title = "Add Project"
        panel.prompt = "Add Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        projects.append(Project(abs_path: url.path))
        app.projects = projects
    }
}
