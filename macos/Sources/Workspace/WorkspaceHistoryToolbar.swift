//
//  WorkSpaceStoreContentToolbar.swift
//  Odyssey
//
//  Created by Adrian Hess on 07/07/26.
//

import AppKit

final class WorkspaceHistoryToolbar: NSView {
    fileprivate enum Metrics {
        static let height: CGFloat = 32
        static let buttonSize: CGFloat = 14
        static let buttonSpacing: CGFloat = 8
        static let leadingPadding: CGFloat = 10
        static let trailingPadding: CGFloat = 10
    }

    private var trackingArea: NSTrackingArea?
    private var isHoveringControls = false {
        didSet {
            closeButton.showsSymbol = isHoveringControls
            minimizeButton.showsSymbol = isHoveringControls
        }
    }

    private lazy var closeButton = TrafficLightButton(
        normalColor: NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1.0),
        borderColor: NSColor(calibratedRed: 0.86, green: 0.22, blue: 0.20, alpha: 1.0),
        symbol: .close,
        action: #selector(closeWindow),
        target: self,
        accessibilityLabel: "Close"
    )

    private lazy var minimizeButton = TrafficLightButton(
        normalColor: NSColor(calibratedRed: 1.0, green: 0.75, blue: 0.20, alpha: 1.0),
        borderColor: NSColor(calibratedRed: 0.85, green: 0.58, blue: 0.11, alpha: 1.0),
        symbol: .minimize,
        action: #selector(minimizeWindow),
        target: self,
        accessibilityLabel: "Minimize"
    )

    private lazy var createButton: NSButton = {
        let button = NSButton(
            title: "Add Workspace", target: self, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        addSubview(minimizeButton)
        addSubview(createButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Metrics.leadingPadding),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Metrics.buttonSize),
            closeButton.heightAnchor.constraint(equalTo: closeButton.widthAnchor),

            minimizeButton.leadingAnchor.constraint(
                equalTo: closeButton.trailingAnchor, constant: Metrics.buttonSpacing),
            minimizeButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            minimizeButton.widthAnchor.constraint(equalTo: closeButton.widthAnchor),
            minimizeButton.heightAnchor.constraint(equalTo: closeButton.heightAnchor),

            createButton.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Metrics.trailingPadding),
            createButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Metrics.height)
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let controlsFrame = closeButton.frame.union(minimizeButton.frame).insetBy(dx: -4, dy: -4)
        let trackingArea = NSTrackingArea(
            rect: controlsFrame,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHoveringControls = true
    }

    override func mouseExited(with event: NSEvent) {
        isHoveringControls = false
    }

    @objc private func closeWindow() {
        window?.close()
    }

    @objc private func minimizeWindow() {
        window?.miniaturize(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TrafficLightButton: NSControl {
    enum Symbol {
        case close
        case minimize
    }

    private let normalColor: NSColor
    private let borderColor: NSColor
    private let symbol: Symbol
    var showsSymbol = false {
        didSet { needsDisplay = true }
    }
    private var isPressed = false {
        didSet { needsDisplay = true }
    }

    init(
        normalColor: NSColor,
        borderColor: NSColor,
        symbol: Symbol,
        action: Selector,
        target: AnyObject,
        accessibilityLabel: String
    ) {
        self.normalColor = normalColor
        self.borderColor = borderColor
        self.symbol = symbol

        super.init(frame: .zero)

        self.action = action
        self.target = target
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel)
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let color: NSColor
        let strokeColor: NSColor
        let isActive = NSApp.isActive

        if !isActive {
            color = NSColor(calibratedWhite: 0.78, alpha: 1.0)
            strokeColor = NSColor(calibratedWhite: 0.62, alpha: 1.0)
        } else if isPressed {
            color = normalColor.blended(withFraction: 0.18, of: .black) ?? normalColor
            strokeColor = borderColor.blended(withFraction: 0.18, of: .black) ?? borderColor
        } else if showsSymbol {
            color = normalColor.blended(withFraction: 0.04, of: .white) ?? normalColor
            strokeColor = borderColor
        } else {
            color = normalColor
            strokeColor = borderColor
        }

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        if isActive && showsSymbol {
            drawSymbol(
                in: rect, color: borderColor.blended(withFraction: 0.35, of: .black) ?? borderColor)
        }
    }

    private func drawSymbol(in rect: NSRect, color: NSColor) {
        color.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1.3
        path.lineCapStyle = .round

        switch symbol {
        case .close:
            path.move(to: NSPoint(x: rect.minX + 4.2, y: rect.minY + 4.2))
            path.line(to: NSPoint(x: rect.maxX - 4.2, y: rect.maxY - 4.2))
            path.move(to: NSPoint(x: rect.maxX - 4.2, y: rect.minY + 4.2))
            path.line(to: NSPoint(x: rect.minX + 4.2, y: rect.maxY - 4.2))
        case .minimize:
            path.move(to: NSPoint(x: rect.minX + 4, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX - 4, y: rect.midY))
        }

        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        let shouldSendAction =
            isPressed && bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false

        if shouldSendAction {
            sendAction(action, to: target)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowActiveStateChanged),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowActiveStateChanged),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowActiveStateChanged),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowActiveStateChanged),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowActiveStateChanged),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowActiveStateChanged),
            name: NSWindow.didResignMainNotification,
            object: nil
        )
        needsDisplay = true
    }

    @objc private func windowActiveStateChanged() {
        needsDisplay = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
