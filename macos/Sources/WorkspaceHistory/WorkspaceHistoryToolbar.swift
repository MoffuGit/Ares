//
//  WorkSpaceStoreContentToolbar.swift
//  Odyssey
//
//  Created by Adrian Hess on 07/07/26.
//

import AppKit

class WorkspaceHistoryToolbar: NSView {
    fileprivate enum Metrics {
        static let height: CGFloat = 32
        static let trailingPadding: CGFloat = 10
    }

    private weak var app: AppDelegate?

    init(app: AppDelegate) {
        self.app = app

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        guard
            let plusImage = NSImage(
                systemSymbolName: "plus",
                accessibilityDescription: "Add Workspace"
            )
        else { fatalError("SF Symbol 'plus' not available") }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbolImage = plusImage.withSymbolConfiguration(config) ?? plusImage
        let button = NSButton(
            image: symbolImage,
            target: self,
            action: #selector(selectNewWorkspace))
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .inline
        button.controlSize = .regular
        button.isBordered = false
        button.imageScaling = .scaleNone
        button.focusRingType = .none
        addSubview(button)

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Metrics.trailingPadding),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 16),
            button.heightAnchor.constraint(equalTo: button.widthAnchor),
        ])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Metrics.height)
    }

    override var mouseDownCanMoveWindow: Bool { true }

    @objc private func selectNewWorkspace() {
        guard let window else { return }
        app?.selectNewWorkspace(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
