//
//  WorkspaceView.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.
//

import AppKit
import SwiftUI

final class WorkspaceView: NSHostingView<WorkspaceRootView> {
    init(project: Project) {
        super.init(rootView: WorkspaceRootView(project: project))
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

struct WorkspaceRootView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Padding.`2`) {
            Text(project.name)
                .font(Theme.Fonts.`3xl`)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(project.abs_path)
                .font(Theme.Fonts.xs)
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
        .padding(Padding.`4`)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(Theme.Colors.background))
    }
}
