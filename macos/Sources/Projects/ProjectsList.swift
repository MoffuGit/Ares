import AppKit
import Combine
import SwiftUI

class ProjectsList: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let emptyView: ProjectListEmptyView
    private let scrollView = NSScrollView()
    private let tableView: NSTableView = {
        let tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Value"))
        column.title = "Value"
        tableView.addTableColumn(column)
        tableView.headerView = nil

        return tableView
    }()

    @ObservedObject var app: AppDelegate
    private var projects: [Project] = []
    private var cancellables = Set<AnyCancellable>()

    init(app: AppDelegate) {
        self.app = app
        self.emptyView = ProjectListEmptyView(app: app)

        super.init(frame: .zero)

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(hex: "#080808").cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(hex: "#080808")
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        app.$projects
            .receive(on: RunLoop.main)
            .sink { [weak self] newProjects in
                self?.projects = newProjects
                self?.updateVisibility()
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = NSColor(hex: "#080808")

        scrollView.documentView = tableView
        addSubview(scrollView)
        addSubview(emptyView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyView.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        emptyView.isHidden = !projects.isEmpty
        tableView.isHidden = projects.isEmpty
    }
    private func updateVisibility() {
        let isEmpty = projects.isEmpty
        emptyView.isHidden = !isEmpty
        scrollView.isHidden = isEmpty
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        projects.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("Cell")

        let cell =
            (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
            ?? {
                let textField = NSTextField(labelWithString: "")
                textField.identifier = identifier
                textField.translatesAutoresizingMaskIntoConstraints = false
                return textField
            }()

        cell.stringValue = projects[row].name
        return cell
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class ProjectListEmptyView: NSStackView {
    init(app: AppDelegate) {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .centerX
        spacing = 18

        let titleLabel = NSTextField(labelWithString: "Odyssey")
        titleLabel.font = .systemFont(ofSize: 38, weight: .semibold)
        titleLabel.textColor = .white

        let openButton = OpenProjectButton(app: app)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        addArrangedSubview(titleLabel)
        addArrangedSubview(openButton)

        NSLayoutConstraint.activate([
            openButton.widthAnchor.constraint(equalToConstant: 140),
            openButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class OpenProjectButton: NSControl {
    private let app: AppDelegate
    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "Open Project")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            updateBackgroundColor()
        }
    }

    init(app: AppDelegate) {
        self.app = app

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        updateBackgroundColor()

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSImage(
            systemSymbolName: "folder", accessibilityDescription: "Open Project")
        imageView.contentTintColor = .white

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white

        addSubview(imageView)
        addSubview(label)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),

            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor =
            (!isHovered ? NSColor.systemBlue : NSColor.systemBlue.withAlphaComponent(0.6)).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        selectNewProject()
    }

    private func selectNewProject() {
        let panel = NSOpenPanel()
        panel.title = "Add Project"
        panel.prompt = "Add Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        app.addProject(project: Project(abs_path: url.path))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
