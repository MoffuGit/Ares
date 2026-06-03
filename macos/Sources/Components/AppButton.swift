import AppKit

final class AppButton: NSControl {
    var title: String {
        didSet {
            titleLabel.stringValue = title
            imageView.image = makeSymbolImage()
        }
    }

    var symbolName: String {
        didSet {
            imageView.image = makeSymbolImage()
        }
    }

    var backgroundColor: NSColor {
        didSet { updateBackgroundColor() }
    }

    var hoverBackgroundColor: NSColor {
        didSet { updateBackgroundColor() }
    }

    var foregroundColor: NSColor {
        didSet {
            titleLabel.textColor = foregroundColor
            imageView.contentTintColor = foregroundColor
        }
    }

    private let contentView = NSView()
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false { didSet { updateBackgroundColor() } }
    private var isPressed = false { didSet { updatePressedState() } }

    init(
        title: String,
        symbolName: String,
        backgroundColor: NSColor = .systemBlue,
        hoverBackgroundColor: NSColor = NSColor.systemBlue.withAlphaComponent(0.6),
        foregroundColor: NSColor = .white
    ) {
        self.title = title
        self.symbolName = symbolName
        self.backgroundColor = backgroundColor
        self.hoverBackgroundColor = hoverBackgroundColor
        self.foregroundColor = foregroundColor

        super.init(frame: .zero)

        wantsLayer = true
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.cornerRadius = 8
        updateBackgroundColor()

        contentView.translatesAutoresizingMaskIntoConstraints = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = makeSymbolImage()
        imageView.contentTintColor = foregroundColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = foregroundColor
        titleLabel.stringValue = title

        addSubview(contentView)
        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
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
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isPressed = bounds.contains(point) && isEnabled
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isPressed = false

        guard bounds.contains(point), isEnabled else { return }

        sendAction(action, to: target)
    }

    private func makeSymbolImage() -> NSImage? {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = (isHovered ? hoverBackgroundColor : backgroundColor).cgColor
    }

    private func updatePressedState() {
        let scale: CGFloat = isPressed ? 0.94 : 1

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
