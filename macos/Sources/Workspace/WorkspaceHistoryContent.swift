//
//  WorksapceListContent.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/07/26.
//

import AppKit

class WorkspaceHistoryContent: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let workspaces: [Odyssey.SerializedWorkspace]
    private let workspaceTableView = NSTableView()
    private weak let app: AppDelegate?

    init(app: AppDelegate, workspaces: Odyssey.SerializedWorkspaces) {
        self.workspaces = workspaces.workspaces
        self.app = app

        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false

        let tableView = workspaceTableView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedWorkspace)
        tableView.headerView = nil
        tableView.rowHeight = 54
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Workspace"))
        column.title = "Workspace"
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        self.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: self.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])

        let emptyView = NSTextField(labelWithString: "No workspaces found")

        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.alignment = .center
        emptyView.font = .systemFont(ofSize: 17, weight: .medium)
        emptyView.textColor = .secondaryLabelColor
        self.addSubview(emptyView)

        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])

        let isEmpty = self.workspaces.isEmpty
        emptyView.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
    }

    @objc func openSelectedWorkspace() {
        let row = workspaceTableView.clickedRow
        guard workspaces.indices.contains(row) else { return }

        let workspace = workspaces[row]
        app?.openWorkspace(workspace)
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
            tableView.makeView(withIdentifier: identifier, owner: self) as? WorkspaceStoreEntryView
            ?? WorkspaceStoreEntryView()

        cell.identifier = identifier
        cell.title = workspace.displayPath
        cell.isFocused = tableView.selectedRow == row
        cell.isPreviousFocused = tableView.selectedRow >= 0 && tableView.selectedRow == row - 1
        cell.isLast = row == workspaces.count - 1
        cell.layer?.zPosition = tableView.selectedRow == row ? 1 : 0

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        workspaceTableView.reloadData(
            forRowIndexes: IndexSet(integersIn: 0..<workspaceTableView.numberOfRows),
            columnIndexes: IndexSet(integer: 0)
        )
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class WorkspaceStoreEntryView: NSTableCellView {
    var title = "" {
        didSet { textField?.stringValue = title }
    }
    var isFocused = false {
        didSet { needsDisplay = true }
    }
    var isPreviousFocused = false {
        didSet { needsDisplay = true }
    }
    var isLast = false {
        didSet { needsDisplay = true }
    }

    private let label = NSTextField(labelWithString: "")
    private let focusedBorderColor = NSColor.systemBlue
    private let borderColor = NSColor.separatorColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        textField = label
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let border = isFocused ? focusedBorderColor : borderColor
        let topBorder = isFocused || isPreviousFocused ? focusedBorderColor : borderColor

        topBorder.setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        if isLast {
            border.setFill()
            NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1).fill()
        }

        if isFocused {
            border.setFill()
            NSRect(x: bounds.minX, y: bounds.minY, width: 1, height: bounds.height).fill()
            NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
