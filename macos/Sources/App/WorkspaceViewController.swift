//
//  WorkspaceViewController.swift
//  Odyssey
//
//  Created by Amp on 03/07/26.
//

import AppKit
import Observation

final class WorkspaceViewController: NSViewController {
    private let workspace: Odyssey.Workspace
    private let countLabel = NSTextField(labelWithString: "")
    private var observationToken: Any?

    init(workspace: Odyssey.Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 270))
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(countLabel)
        NSLayoutConstraint.activate([
            countLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateCountLabel()
    }

    private func updateCountLabel() {
        withObservationTracking {
            _ = workspace.updateGeneration
            countLabel.stringValue = "Workspace count: \(workspace.count)"
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor [self] in
                self.updateCountLabel()
            }
        }
    }
}
