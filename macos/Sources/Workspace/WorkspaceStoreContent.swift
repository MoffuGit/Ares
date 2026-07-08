//
//  WorksapceListContent.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/07/26.
//

import AppKit

class WorkspaceStoreContent: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let workspaces: [Odyssey.SerializedWorkspace]
    private let stackView = NSStackView()
    private let toolbar = WorkspaceStoreToolbar(frame: .zero)
    private let contentView = NSView()
    private let emptyView = NSTextField(labelWithString: "No workspaces found")
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

    init(workspaces: Odyssey.SerializedWorkspaces) {
        self.workspaces = workspaces.workspaces

        super.init(frame: .zero)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 0
        addSubview(stackView)
        stackView.addArrangedSubview(toolbar)
        stackView.addArrangedSubview(contentView)
        stackView.setCustomSpacing(0, after: toolbar)

        setupContentView()
        setupEmptyView()
        setupTableView()
        updateVisibility()

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupContentView() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupEmptyView() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.alignment = .center
        emptyView.font = .systemFont(ofSize: 17, weight: .medium)
        emptyView.textColor = .secondaryLabelColor
        contentView.addSubview(emptyView)

        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    private func setupTableView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
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
