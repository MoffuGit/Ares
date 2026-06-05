import AppKit
import Combine
import SwiftUI

class ProjectsList: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var emptyView: NSHostingView<ProjectEmptyView>!
    private let scrollView = NSScrollView()
    private lazy var tableView: NSTableView = {
        let tableView = NSTableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedWorkspace)

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

        super.init(frame: .zero)

        wantsLayer = true
        layer?.setBackgroundColor(Theme.Colors.background)

        emptyView = NSHostingView(rootView: ProjectEmptyView(app: app))
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.wantsLayer = true
        emptyView.layer?.backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(Theme.Colors.background)
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
        tableView.backgroundColor = NSColor(Theme.Colors.background)
        tableView.rowHeight = 85
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.allowsEmptySelection = false

        scrollView.documentView = tableView

        addSubview(scrollView)
        addSubview(emptyView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyView.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyView.topAnchor.constraint(equalTo: topAnchor),
            emptyView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateVisibility()
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
            (tableView.makeView(withIdentifier: identifier, owner: self)
                as? NSHostingView<ProjectListEntryView>)
            ?? {
                let hostingView = NSHostingView(
                    rootView: ProjectListEntryView(
                        project: projects[row],
                        isFocused: tableView.selectedRow == row,
                        isPreviousFocused: tableView.selectedRow == row - 1,
                        isLast: row == projects.count - 1
                    ))
                hostingView.identifier = identifier
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                return hostingView
            }()

        cell.rootView = ProjectListEntryView(
            project: projects[row],
            isFocused: tableView.selectedRow == row,
            isPreviousFocused: tableView.selectedRow == row - 1,
            isLast: row == projects.count - 1
        )
        cell.layer?.zPosition = tableView.selectedRow == row ? 1 : 0
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        tableView.reloadData(
            forRowIndexes: IndexSet(integersIn: 0..<tableView.numberOfRows),
            columnIndexes: IndexSet(integer: 0)
        )
    }

    @objc private func openSelectedWorkspace(_ sender: NSTableView) {
        openWorkspace(at: sender.clickedRow)
    }

    private func openWorkspace(at row: Int) {
        guard projects.indices.contains(row) else { return }
        app.openWorkspace(for: projects[row])
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        window?.makeFirstResponder(tableView)
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct ProjectListEntryView: View {
    let project: Project
    let isFocused: Bool
    let isPreviousFocused: Bool
    let isLast: Bool

    private var borderColor: Color {
        if isFocused {
            Color(Theme.Colors.ring)
        } else {
            Color(Theme.Colors.border)
        }
    }

    private var topBorderColor: Color {
        if isFocused || isPreviousFocused {
            Color(Theme.Colors.ring)
        } else {
            Color(Theme.Colors.border)
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text(project.name)
                .font(Theme.Fonts.xl)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text(project.abs_path)
                .font(Theme.Fonts.xs)
                .foregroundStyle(Color(Theme.Colors.mutedForeground))
                .lineLimit(1)
        }
        .padding(Padding.`3`)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment.topLeading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(topBorderColor)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            if isLast {
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .leading) {
            if isFocused {
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 1)
            }
        }
        .overlay(alignment: .trailing) {
            if isFocused {
                Rectangle()
                    .fill(borderColor)
                    .frame(width: 1)
            }
        }
    }
}
