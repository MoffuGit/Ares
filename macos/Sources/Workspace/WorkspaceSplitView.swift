//
//  WorkspaceSplitView.swift
//  Odyssey
//
//  Created by Adrian Hess on 16/07/26.
//

import AppKit

/// A fixed three-pane horizontal layout (left sidebar | content | right sidebar)
/// built on top of `NSStackView`. The side panes have mutable widths; the center
/// pane absorbs all remaining space. Each side is separated from the center by a
/// draggable divider that also collapses/restores the adjacent pane on double click.
final class WorkspaceSplitView: NSStackView {
    let leftPane = WorkspacePaneView()
    let centerPane = WorkspacePaneView()
    let rightPane = WorkspacePaneView()

    private let leftDivider = WorkspaceDividerView(side: .left)
    private let rightDivider = WorkspaceDividerView(side: .right)

    private enum Metrics {
        static let dividerWidth: CGFloat = 8
        static let minimumCenterWidth: CGFloat = 100
        static let defaultSidebarWidth: CGFloat = 220
        static let maximumSidebarWidth: CGFloat = 480
    }

    private struct SidebarState {
        var expandedWidth: CGFloat = Metrics.defaultSidebarWidth
        var isCollapsed = false

        var effectiveWidth: CGFloat {
            isCollapsed ? 0 : expandedWidth
        }
    }

    private var leftState = SidebarState()
    private var rightState = SidebarState()

    private var leftWidthConstraint: NSLayoutConstraint!
    private var rightWidthConstraint: NSLayoutConstraint!

    private struct ActiveDrag {
        let side: WorkspaceDividerView.Side
        let startWidth: CGFloat
    }

    private var activeDrag: ActiveDrag?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        orientation = .horizontal
        distribution = .fill
        spacing = 0
        translatesAutoresizingMaskIntoConstraints = false

        // Expand to fill the vertical space offered by the containing stack.
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        for view in [leftPane, leftDivider, centerPane, rightDivider, rightPane] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(view)
        }

        leftDivider.widthAnchor.constraint(equalToConstant: Metrics.dividerWidth).isActive = true
        rightDivider.widthAnchor.constraint(equalToConstant: Metrics.dividerWidth).isActive = true

        centerPane.widthAnchor.constraint(
            greaterThanOrEqualToConstant: Metrics.minimumCenterWidth
        ).isActive = true

        // The center pane must yield to the side panes and fill all remaining space.
        centerPane.setContentHuggingPriority(.init(1), for: .horizontal)
        centerPane.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        centerPane.setContentHuggingPriority(.defaultLow, for: .vertical)

        leftWidthConstraint = leftPane.widthAnchor.constraint(
            equalToConstant: leftState.effectiveWidth
        )
        rightWidthConstraint = rightPane.widthAnchor.constraint(
            equalToConstant: rightState.effectiveWidth
        )
        // Just below required so the center minimum can win if the host is too narrow.
        leftWidthConstraint.priority = .init(999)
        rightWidthConstraint.priority = .init(999)
        leftWidthConstraint.isActive = true
        rightWidthConstraint.isActive = true

        leftPane.isHidden = leftState.isCollapsed
        rightPane.isHidden = rightState.isCollapsed

        installGestureRecognizers(for: .left, on: leftDivider)
        installGestureRecognizers(for: .right, on: rightDivider)
    }

    private func installGestureRecognizers(for side: WorkspaceDividerView.Side, on divider: NSView) {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        divider.addGestureRecognizer(pan)

        let doubleClick = NSClickGestureRecognizer(
            target: self, action: #selector(handleDoubleClick(_:))
        )
        doubleClick.numberOfClicksRequired = 2
        divider.addGestureRecognizer(doubleClick)
    }

    // MARK: - Gesture handling

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        guard let divider = recognizer.view as? WorkspaceDividerView else { return }
        let side = divider.side

        switch recognizer.state {
        case .began:
            activeDrag = ActiveDrag(
                side: side,
                startWidth: state(for: side).effectiveWidth
            )
            // Disable cursor rects so neighboring views can't override the
            // resize cursor while the pointer travels outside the divider.
            window?.disableCursorRects()
            NSCursor.resizeLeftRight.set()
        case .changed:
            guard let drag = activeDrag else { return }
            let translation = recognizer.translation(in: self)
            let proposed: CGFloat
            if side == .left {
                proposed = drag.startWidth + translation.x
            } else {
                proposed = drag.startWidth - translation.x
            }
            setExpandedWidth(proposed, for: side)
            NSCursor.resizeLeftRight.set()
        case .ended, .cancelled, .failed:
            if activeDrag != nil {
                window?.enableCursorRects()
            }
            activeDrag = nil
        default:
            break
        }
    }

    @objc private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        guard let divider = recognizer.view as? WorkspaceDividerView else { return }
        toggleCollapsed(divider.side)
    }

    // MARK: - State mutations

    private func setExpandedWidth(_ width: CGFloat, for side: WorkspaceDividerView.Side) {
        let clamped = min(max(width, 0), maximumWidth(for: side))
        if side == .left {
            leftState.expandedWidth = clamped
            leftState.isCollapsed = false
            leftPane.isHidden = false
            leftWidthConstraint.constant = clamped
        } else {
            rightState.expandedWidth = clamped
            rightState.isCollapsed = false
            rightPane.isHidden = false
            rightWidthConstraint.constant = clamped
        }
        layoutSubtreeIfNeeded()
    }

    private func toggleCollapsed(_ side: WorkspaceDividerView.Side) {
        if side == .left {
            if leftState.isCollapsed {
                leftState.expandedWidth = min(
                    leftState.expandedWidth, maximumWidth(for: .left)
                )
                leftState.isCollapsed = false
            } else {
                leftState.isCollapsed = true
            }
            leftPane.isHidden = leftState.isCollapsed
            leftWidthConstraint.constant = leftState.effectiveWidth
        } else {
            if rightState.isCollapsed {
                rightState.expandedWidth = min(
                    rightState.expandedWidth, maximumWidth(for: .right)
                )
                rightState.isCollapsed = false
            } else {
                rightState.isCollapsed = true
            }
            rightPane.isHidden = rightState.isCollapsed
            rightWidthConstraint.constant = rightState.effectiveWidth
        }
        layoutSubtreeIfNeeded()
    }

    // MARK: - Geometry helpers

    private func state(for side: WorkspaceDividerView.Side) -> SidebarState {
        side == .left ? leftState : rightState
    }

    private func maximumWidth(for side: WorkspaceDividerView.Side) -> CGFloat {
        let otherWidth = (side == .left ? rightState : leftState).effectiveWidth
        let available = bounds.width
            - otherWidth
            - 2 * Metrics.dividerWidth
            - Metrics.minimumCenterWidth
        return min(Metrics.maximumSidebarWidth, max(0, available))
    }
}

/// A plain, transparent host view for pane content. The split view only manages
/// the geometry; whatever is later embedded here controls its own appearance.
final class WorkspacePaneView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The draggable, double-clickable separator between a sidebar and the center pane.
/// It draws a centered 1-point separator line and only reports its side; all layout
/// and resize logic lives in `WorkspaceSplitView`.
private final class WorkspaceDividerView: NSView {
    enum Side {
        case left
        case right
    }

    let side: Side

    init(side: Side) {
        self.side = side
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.separatorColor.setFill()
        // Draw the line on the edge adjacent to the center pane.
        let lineX: CGFloat
        if side == .left {
            lineX = bounds.maxX - 0.5
        } else {
            lineX = bounds.minX + 0.5
        }
        NSRect(x: lineX, y: bounds.minY, width: 1, height: bounds.height).fill()
    }
}
