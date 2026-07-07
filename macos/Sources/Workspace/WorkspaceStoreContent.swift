//
//  WorksapceListContent.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/07/26.
//

import AppKit

final class WorkspaceStoreContent: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let workspaces: [Odyssey.SerializedWorkspace]
    private let createWorkspace: () -> Void
    private let emptyView = NSTextField(labelWithString: "No workspaces found")
    private let createButton = NSButton(title: "New Workspace", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private lazy var tableView: NSTableView = {
        let tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.rowHeight = 54
        tableView.style = .plain

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Workspace"))
        column.title = "Workspace"
        tableView.addTableColumn(column)

        return tableView
    }()

    init(workspaces: Odyssey.SerializedWorkspaces, createWorkspace: @escaping () -> Void) {
        self.workspaces = workspaces.workspaces
        self.createWorkspace = createWorkspace

        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        setupCreateButton()
        setupEmptyView()
        setupTableView()
        updateVisibility()
    }

    private func setupCreateButton() {
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.bezelStyle = .rounded
        createButton.target = self
        createButton.action = #selector(createWorkspaceButtonPressed)
        addSubview(createButton)

        NSLayoutConstraint.activate([
            createButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            createButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    private func setupEmptyView() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.alignment = .center
        emptyView.font = .systemFont(ofSize: 17, weight: .medium)
        emptyView.textColor = .secondaryLabelColor
        addSubview(emptyView)

        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func setupTableView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: createButton.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func createWorkspaceButtonPressed() {
        createWorkspace()
    }

    private func updateVisibility() {
        let isEmpty = workspaces.isEmpty
        emptyView.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        workspaces.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let identifier = NSUserInterfaceItemIdentifier("WorkspaceCell")
        let workspace = workspaces[row]
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? NSTableCellView()

        cell.identifier = identifier
        cell.textField = cell.textField ?? NSTextField(labelWithString: "")
        cell.textField?.translatesAutoresizingMaskIntoConstraints = false
        cell.textField?.lineBreakMode = .byTruncatingMiddle
        cell.textField?.stringValue = workspace.displayPath

        if cell.textField?.superview == nil, let textField = cell.textField {
            cell.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -16),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        return cell
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
