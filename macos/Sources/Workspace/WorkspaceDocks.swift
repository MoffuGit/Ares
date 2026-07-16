//
//  WorkspaceSplitView.swift
//  Odyssey
//
//  Created by Adrian Hess on 16/07/26.
//

import AppKit

class WorkspaceDocks: NSStackView {
    let leftDock = WorkspaceDock()
    let rightDock = WorkspaceDock()
    let centerWrapper = NSView()

    private let leftDivider = WorkspaceDividerView(side: .left)
    private let rightDivider = WorkspaceDividerView(side: .right)

    private enum Metrics {
        static let dividerWidth: CGFloat = 8
        static let collapsedDividerWidth: CGFloat = 16
        static let minimumSidebarWidth: CGFloat = 4
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

    private var leftDividerWidthConstraint: NSLayoutConstraint!
    private var rightDividerWidthConstraint: NSLayoutConstraint!
    private var leftDividerLeadingConstraint: NSLayoutConstraint!
    private var rightDividerLeadingConstraint: NSLayoutConstraint!

    private struct ActiveDrag {
        let side: WorkspaceDividerView.Side
        let startWidth: CGFloat
    }

    private var activeDrag: ActiveDrag?

    init(center: NSView) {
        super.init(frame: .zero)

        orientation = .horizontal
        distribution = .fill
        spacing = 0
        translatesAutoresizingMaskIntoConstraints = false

        // Expand to fill the vertical space offered by the containing stack.
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

        for view in [leftDock, centerWrapper, rightDock] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(view)
        }

        centerWrapper.widthAnchor.constraint(
            greaterThanOrEqualToConstant: Metrics.minimumCenterWidth
        ).isActive = true

        centerWrapper.setContentHuggingPriority(.init(1), for: .horizontal)
        centerWrapper.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        centerWrapper.setContentHuggingPriority(.defaultLow, for: .vertical)

        leftWidthConstraint = leftDock.widthAnchor.constraint(
            equalToConstant: leftState.effectiveWidth
        )
        rightWidthConstraint = rightDock.widthAnchor.constraint(
            equalToConstant: rightState.effectiveWidth
        )
        // Just below required so the center minimum can win if the host is too narrow.
        leftWidthConstraint.priority = .init(999)
        rightWidthConstraint.priority = .init(999)
        leftWidthConstraint.isActive = true
        rightWidthConstraint.isActive = true

        // Dividers overlay on top of the panes, centered on each boundary so
        // they don't consume any layout width.
        for divider in [leftDivider, rightDivider] {
            divider.translatesAutoresizingMaskIntoConstraints = false
            addSubview(divider)
            divider.topAnchor.constraint(equalTo: topAnchor).isActive = true
            divider.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        }

        leftDividerWidthConstraint = leftDivider.widthAnchor.constraint(
            equalToConstant: effectiveDividerWidth(collapsed: leftState.isCollapsed)
        )
        rightDividerWidthConstraint = rightDivider.widthAnchor.constraint(
            equalToConstant: effectiveDividerWidth(collapsed: rightState.isCollapsed)
        )
        leftDividerWidthConstraint.isActive = true
        rightDividerWidthConstraint.isActive = true

        leftDividerLeadingConstraint = leftDivider.leadingAnchor.constraint(
            equalTo: leftDock.trailingAnchor,
            constant: -effectiveDividerWidth(collapsed: leftState.isCollapsed) / 2
        )
        rightDividerLeadingConstraint = rightDivider.leadingAnchor.constraint(
            equalTo: rightDock.leadingAnchor,
            constant: -effectiveDividerWidth(collapsed: rightState.isCollapsed) / 2
        )
        leftDividerLeadingConstraint.isActive = true
        rightDividerLeadingConstraint.isActive = true

        installGestureRecognizers(for: .left, on: leftDivider)
        installGestureRecognizers(for: .right, on: rightDivider)
    
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installGestureRecognizers(for side: WorkspaceDividerView.Side, on divider: NSView)
    {
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
                // Re-evaluate hover based on the actual cursor position, since
                // mouseExited may not have fired during the drag and the
                // tracking area may fire a stale mouseEntered on re-enable.
                let cursorInWindow = window?.mouseLocationOutsideOfEventStream
                let cursorInDivider = cursorInWindow.flatMap {
                    divider.convert($0, from: nil)
                }
                divider.isHovering =
                    cursorInDivider.map {
                        divider.bounds.contains($0)
                    } ?? false
            }
            activeDrag = nil
        default:
            break
        }
    }

    @objc private func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        guard let divider = recognizer.view as? WorkspaceDividerView else { return }
        // Reset hover state since the collapse/expand can move the divider out
        // from under the cursor without a mouseExited being delivered.
        divider.isHovering = false
        toggleCollapsed(divider.side)
    }

    // MARK: - State mutations

    private func setExpandedWidth(_ width: CGFloat, for side: WorkspaceDividerView.Side) {
        let clamped = min(max(width, Metrics.minimumSidebarWidth), maximumWidth(for: side))
        if side == .left {
            leftState.expandedWidth = clamped
            leftState.isCollapsed = false
            leftWidthConstraint.constant = clamped
            leftDivider.isCollapsed = false
            updateDividerConstraints(for: .left)
        } else {
            rightState.expandedWidth = clamped
            rightState.isCollapsed = false
            rightWidthConstraint.constant = clamped
            rightDivider.isCollapsed = false
            updateDividerConstraints(for: .right)
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
            leftWidthConstraint.constant = leftState.effectiveWidth
            leftDivider.isCollapsed = leftState.isCollapsed
            updateDividerConstraints(for: .left)
        } else {
            if rightState.isCollapsed {
                rightState.expandedWidth = min(
                    rightState.expandedWidth, maximumWidth(for: .right)
                )
                rightState.isCollapsed = false
            } else {
                rightState.isCollapsed = true
            }
            rightWidthConstraint.constant = rightState.effectiveWidth
            rightDivider.isCollapsed = rightState.isCollapsed
            updateDividerConstraints(for: .right)
        }
        layoutSubtreeIfNeeded()
    }

    // MARK: - Geometry helpers

    private func state(for side: WorkspaceDividerView.Side) -> SidebarState {
        side == .left ? leftState : rightState
    }

    private func maximumWidth(for side: WorkspaceDividerView.Side) -> CGFloat {
        let otherWidth = (side == .left ? rightState : leftState).effectiveWidth
        let available =
            bounds.width
            - otherWidth
            - Metrics.minimumCenterWidth
        return min(Metrics.maximumSidebarWidth, max(0, available))
    }

    private func effectiveDividerWidth(collapsed: Bool) -> CGFloat {
        collapsed ? Metrics.collapsedDividerWidth : Metrics.dividerWidth
    }

    private func updateDividerConstraints(for side: WorkspaceDividerView.Side) {
        let collapsed = side == .left ? leftState.isCollapsed : rightState.isCollapsed
        let width = effectiveDividerWidth(collapsed: collapsed)
        if side == .left {
            leftDividerWidthConstraint.constant = width
            leftDividerLeadingConstraint.constant = -width / 2
        } else {
            rightDividerWidthConstraint.constant = width
            rightDividerLeadingConstraint.constant = -width / 2
        }
    }
}

class WorkspaceDock: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class WorkspaceDividerView: NSView {
    enum Side {
        case left
        case right
    }

    let side: Side

    var isCollapsed = false {
        didSet {
            guard oldValue != isCollapsed else { return }
            needsDisplay = true
        }
    }

    var isHovering = false {
        didSet {
            guard oldValue != isHovering else { return }
            needsDisplay = true
        }
    }

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove any stale tracking areas we own.
        trackingAreas
            .filter { $0.owner === self }
            .forEach { removeTrackingArea($0) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.separatorColor.setFill()
        let lineWidth: CGFloat
        if isCollapsed && isHovering {
            lineWidth = 4
        } else if isHovering {
            lineWidth = 2
        } else {
            lineWidth = 1
        }
        let lineX = bounds.midX - lineWidth / 2
        NSRect(x: lineX, y: bounds.minY, width: lineWidth, height: bounds.height).fill()
    }
}
