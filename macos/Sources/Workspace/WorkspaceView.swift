//
//  WorkspaceView.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.
//

import AppKit
import Combine
import SwiftUI

final class WorkspaceView: NSHostingView<WorkspaceRootView> {
    init(project: Project, workspace: Odyssey.Workspace) {
        let model = WorkspaceModel(workspace: workspace)
        super.init(rootView: WorkspaceRootView(project: project, model: model))
    }

    @available(*, unavailable)
    @MainActor dynamic required init(rootView: WorkspaceRootView) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WorkspaceModel: ObservableObject {
    @Published var count: UInt
    private let workspace: Odyssey.Workspace

    init(workspace: Odyssey.Workspace) {
        self.workspace = workspace
        self.count = workspace.count
        self.workspace.onChange = { [weak self] count in
            self?.count = count
        }
    }
}

struct WorkspaceRootView: View {
    let project: Project
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: Padding.`2`) {
            Text(project.name)
                .font(Theme.Fonts.`3xl`)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(project.displayPath)
                .font(Theme.Fonts.xs)
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            Text("Count: \(model.count)")
                .font(Theme.Fonts.lg)
                .foregroundStyle(.white)
        }
        .padding(Padding.`4`)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(Theme.Colors.background))
    }
}
