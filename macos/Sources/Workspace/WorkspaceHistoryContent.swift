//
//  WorksapceListContent.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/07/26.
//

import AppKit
import os

class WorkspaceHistoryContent: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var workspaces: [Odyssey.SerializedWorkspace]
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
        tableView.rowHeight = 80
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.backgroundColor = .clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Workspace"))
        column.title = "Workspace"
        tableView.addTableColumn(column)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
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
        cell.workspaceID = workspace.id
        cell.timestamp = workspace.timestamp
        cell.paths = workspace.paths
        cell.isFocused = tableView.selectedRow == row
        cell.isPreviousFocused = tableView.selectedRow >= 0 && tableView.selectedRow == row - 1
        cell.isLast = row == workspaces.count - 1
        cell.layer?.zPosition = tableView.selectedRow == row ? 1 : 0

        cell.onDelete = { [weak self] in
            self?.deleteWorkspace(at: row)
        }

        return cell
    }

    private func deleteWorkspace(at row: Int) {
        guard workspaces.indices.contains(row) else { return }
        let workspace = workspaces[row]
        guard Odyssey.SerializedWorkspaces.deleteByID(workspace.id) else {
            Odyssey.logger.critical("odyssey_workspace_delete_by_id failed for id \(workspace.id)")
            return
        }

        workspaces.remove(at: row)

        let isEmpty = workspaces.isEmpty
        workspaceTableView.reloadData()

        if let scrollView = workspaceTableView.enclosingScrollView {
            for case let emptyView as NSTextField in subviews where emptyView.stringValue == "No workspaces found" {
                emptyView.isHidden = !isEmpty
                scrollView.isHidden = isEmpty
                break
            }
        }
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
    var workspaceID: Int64 = 0 {
        didSet { updateTopLabel() }
    }
    var timestamp: Int64 = 0 {
        didSet { updateTopLabel() }
    }
    var paths: [String] = [] {
        didSet { updateMiddleLabel() }
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

    var onDelete: (() -> Void)?

    private let stackView = NSStackView()
    private let topLabel = NSTextField(labelWithString: "")
    private let middleLabel = NSTextField(labelWithString: "")
    private let bottomSpacer = NSView()
    private let deleteButton = NSButton()
    private let focusedBorderColor = NSColor.systemBlue
    private let borderColor = NSColor.separatorColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true

        // --- Vertical stack ---
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        addSubview(stackView)

        topLabel.translatesAutoresizingMaskIntoConstraints = false
        topLabel.font = .systemFont(ofSize: 11, weight: .regular)
        topLabel.textColor = .secondaryLabelColor
        topLabel.lineBreakMode = .byTruncatingMiddle
        stackView.addArrangedSubview(topLabel)

        middleLabel.translatesAutoresizingMaskIntoConstraints = false
        middleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        middleLabel.lineBreakMode = .byTruncatingMiddle
        stackView.addArrangedSubview(middleLabel)

        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
        stackView.addArrangedSubview(bottomSpacer)

        // --- Delete button (absolute top-right) ---
        guard
            let minusImage = NSImage(
                systemSymbolName: "minus",
                accessibilityDescription: "Delete Workspace"
            )
        else { fatalError("SF Symbol 'minus' not available") }
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        deleteButton.image = minusImage.withSymbolConfiguration(symbolConfig) ?? minusImage
        deleteButton.imagePosition = .imageOnly
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .inline
        deleteButton.controlSize = .regular
        deleteButton.isBordered = false
        deleteButton.imageScaling = .scaleNone
        deleteButton.focusRingType = .none
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            deleteButton.centerYAnchor.constraint(
                equalTo: topAnchor, constant: 16),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            deleteButton.widthAnchor.constraint(equalToConstant: 16),
            deleteButton.heightAnchor.constraint(equalTo: deleteButton.widthAnchor),
        ])
    }

    @objc private func deleteButtonClicked() {
        onDelete?()
    }

    private func updateTopLabel() {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        topLabel.stringValue = "[ \(workspaceID) ] \(formatter.string(from: date))"
    }

    private func updateMiddleLabel() {
        let names = paths.map { URL(fileURLWithPath: $0).lastPathComponent }
        middleLabel.stringValue = names.isEmpty ? "No path" : names.joined(separator: ", ")
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
