import AppKit
import Combine
import SwiftUI

class ProjectsList: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var emptyView: NSHostingView<ProjectEmptyView>!
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

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: "#080808").cgColor

        emptyView = NSHostingView(rootView: ProjectEmptyView(app: app))
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.wantsLayer = true
        emptyView.layer?.backgroundColor = .clear

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
        tableView.rowHeight = 120
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
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 45),
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
                        isFirst: row == 0
                    ))
                hostingView.identifier = identifier
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                return hostingView
            }()

        cell.rootView = ProjectListEntryView(
            project: projects[row],
            isFocused: tableView.selectedRow == row,
            isFirst: row == 0
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        tableView.reloadData()
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
    let isFirst: Bool

    private var borderColor: Color {
        if isFocused {
            .blue
        } else {

            Color(NSColor(hex: "#393939"))
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            Text(project.name)
                .typography(.`3xl`)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text(project.abs_path)
                .typography(.xs)
                .foregroundStyle(.white.opacity(0.48))
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(Padding.`4`)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment.topLeading)
        .overlay(alignment: .top) {
            if isFirst {
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
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
