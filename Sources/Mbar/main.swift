import AppKit
import ApplicationServices
import CoreGraphics

let appDragPasteboardType = NSPasteboard.PasteboardType("dev.auhanson.mbar.bundle-id")
let finderBundleID = "com.apple.finder"

enum Edge: String, CaseIterable {
    case bottom
    case top
    case left
    case right
}

enum BarTheme: String, CaseIterable {
    case `default` = "default"
    case macOSGlass = "macosGlass"

    var displayName: String {
        switch self {
        case .default:
            return "Default"
        case .macOSGlass:
            return "macOS Glass"
        }
    }
}

struct Settings {
    private enum Key {
        static let edge = "edge"
        static let theme = "theme"
        static let autoHide = "autoHide"
        static let mirror = "mirror"
        static let activityMode = "activityMode"
        static let rows = "rows"
        static let barSize = "barSize"
        static let iconSize = "iconSize"
        static let itemSpacing = "itemSpacing"
        static let showFinder = "showFinder"
        static let showApplications = "showApplications"
        static let showTrash = "showTrash"
        static let pinnedBundleIDs = "pinnedBundleIDs"
    }

    static var edge: Edge {
        get { Edge(rawValue: UserDefaults.standard.string(forKey: Key.edge) ?? "") ?? .bottom }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.edge) }
    }

    static var theme: BarTheme {
        get { BarTheme(rawValue: UserDefaults.standard.string(forKey: Key.theme) ?? "") ?? .default }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.theme) }
    }

    static var autoHide: Bool {
        get { UserDefaults.standard.object(forKey: Key.autoHide) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoHide) }
    }

    static var mirror: Bool {
        get { UserDefaults.standard.object(forKey: Key.mirror) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Key.mirror) }
    }

    static var activityMode: Bool {
        get { UserDefaults.standard.bool(forKey: Key.activityMode) }
        set { UserDefaults.standard.set(newValue, forKey: Key.activityMode) }
    }

    static var rows: Int {
        get { max(1, min(5, UserDefaults.standard.integer(forKey: Key.rows) == 0 ? 1 : UserDefaults.standard.integer(forKey: Key.rows))) }
        set { UserDefaults.standard.set(max(1, min(5, newValue)), forKey: Key.rows) }
    }

    static var barSize: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: Key.barSize)
            return value == 0 ? 78 : CGFloat(max(54, min(180, value)))
        }
        set { UserDefaults.standard.set(Double(max(54, min(180, newValue))), forKey: Key.barSize) }
    }

    static var iconSize: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: Key.iconSize)
            return value == 0 ? 42 : CGFloat(max(24, min(96, value)))
        }
        set { UserDefaults.standard.set(Double(max(24, min(96, newValue))), forKey: Key.iconSize) }
    }

    static var itemSpacing: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: Key.itemSpacing)
            return value == 0 ? 9 : CGFloat(max(0, min(32, value)))
        }
        set { UserDefaults.standard.set(Double(max(0, min(32, newValue))), forKey: Key.itemSpacing) }
    }

    static var showFinder: Bool {
        get { UserDefaults.standard.bool(forKey: Key.showFinder) }
        set { UserDefaults.standard.set(newValue, forKey: Key.showFinder) }
    }

    static var showApplications: Bool {
        get { UserDefaults.standard.object(forKey: Key.showApplications) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.showApplications) }
    }

    static var showTrash: Bool {
        get { UserDefaults.standard.object(forKey: Key.showTrash) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.showTrash) }
    }

    static var pinnedBundleIDs: [String] {
        get {
            let saved = UserDefaults.standard.stringArray(forKey: Key.pinnedBundleIDs) ?? []
            let filtered = saved.filter { showFinder || $0 != finderBundleID }
            if filtered.count != saved.count {
                UserDefaults.standard.set(Array(NSOrderedSet(array: filtered)) as? [String] ?? filtered, forKey: Key.pinnedBundleIDs)
            }
            return filtered
        }
        set {
            let filtered = newValue.filter { showFinder || $0 != finderBundleID }
            UserDefaults.standard.set(Array(NSOrderedSet(array: filtered)) as? [String] ?? filtered, forKey: Key.pinnedBundleIDs)
        }
    }
}

struct WindowInfo {
    let ownerPID: pid_t
    let title: String
    let bounds: CGRect
}

struct WindowListItem {
    let title: String
    let open: () -> Void
}

struct ProcessSample {
    let cpu: String
    let memory: String
}

@MainActor
final class HoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onDropBundleID: ((String, CGPoint) -> Bool)?
    var onDragBundleID: ((String, CGPoint) -> Void)?
    var onMenu: (() -> NSMenu)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([appDragPasteboardType])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: appDragPasteboardType) == nil ? [] : .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let bundleID = sender.draggingPasteboard.string(forType: appDragPasteboardType) else { return [] }
        onDragBundleID?(bundleID, convert(sender.draggingLocation, from: nil))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onExit?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bundleID = sender.draggingPasteboard.string(forType: appDragPasteboardType) else { return false }
        return onDropBundleID?(bundleID, convert(sender.draggingLocation, from: nil)) ?? false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onMenu?()
    }
}

@MainActor
final class DockBackgroundView: NSVisualEffectView {
    var onDropBundleID: ((String, CGPoint) -> Bool)?
    var onDragBundleID: ((String, CGPoint) -> Void)?
    var onMenu: (() -> NSMenu)?
    private let glassGradientLayer = CAGradientLayer()
    private let glassGradientMaskLayer = CAShapeLayer()
    private var glassCornerRadius: CGFloat = 0
    private var isUsingGlassOverlays = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([appDragPasteboardType])
    }

    override func layout() {
        super.layout()
        updateGlassLayers()
    }

    func applyGlassOverlays(enabled: Bool, cornerRadius: CGFloat) {
        isUsingGlassOverlays = enabled
        glassCornerRadius = cornerRadius
        maskImage = enabled ? Self.roundedMask(size: bounds.size, cornerRadius: cornerRadius) : nil

        if enabled {
            wantsLayer = true
            if glassGradientLayer.superlayer == nil {
                layer?.addSublayer(glassGradientLayer)
            }

            glassGradientLayer.colors = [
                NSColor.white.withAlphaComponent(0.36).cgColor,
                NSColor.white.withAlphaComponent(0.06).cgColor,
                NSColor.white.withAlphaComponent(0.06).cgColor,
                NSColor.white.withAlphaComponent(0.36).cgColor
            ]
            glassGradientLayer.locations = [0, 0.34, 0.66, 1]
            glassGradientLayer.startPoint = CGPoint(x: 0, y: 1)
            glassGradientLayer.endPoint = CGPoint(x: 1, y: 0)
            glassGradientLayer.mask = glassGradientMaskLayer

            glassGradientMaskLayer.fillColor = NSColor.clear.cgColor
            glassGradientMaskLayer.strokeColor = NSColor.black.cgColor
            glassGradientMaskLayer.lineWidth = 1.5
            updateGlassLayers()
        } else {
            glassGradientLayer.removeFromSuperlayer()
            glassGradientLayer.mask = nil
        }
    }

    private func updateGlassLayers() {
        guard isUsingGlassOverlays else { return }
        maskImage = Self.roundedMask(size: bounds.size, cornerRadius: glassCornerRadius)
        glassGradientLayer.frame = bounds
        let strokeInset = glassGradientMaskLayer.lineWidth / 2
        let strokeRect = bounds.insetBy(dx: strokeInset, dy: strokeInset)
        glassGradientMaskLayer.frame = bounds
        glassGradientMaskLayer.path = CGPath(
            roundedRect: strokeRect,
            cornerWidth: max(0, glassCornerRadius - strokeInset),
            cornerHeight: max(0, glassCornerRadius - strokeInset),
            transform: nil
        )
    }

    private static func roundedMask(size: NSSize, cornerRadius: CGFloat) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: cornerRadius, yRadius: cornerRadius).fill()
        image.unlockFocus()
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: appDragPasteboardType) == nil ? [] : .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let bundleID = sender.draggingPasteboard.string(forType: appDragPasteboardType) else { return [] }
        onDragBundleID?(bundleID, convert(sender.draggingLocation, from: nil))
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bundleID = sender.draggingPasteboard.string(forType: appDragPasteboardType) else { return false }
        return onDropBundleID?(bundleID, convert(sender.draggingLocation, from: nil)) ?? false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        onMenu?()
    }
}

@MainActor
final class ApplicationButton: NSButton {
    let url: URL

    init(url: URL, target: AnyObject?, action: Selector?) {
        self.url = url
        super.init(frame: .zero)
        let title = url.deletingPathExtension().lastPathComponent
        self.title = title
        self.image = NSWorkspace.shared.icon(forFile: url.path)
        self.image?.size = NSSize(width: 44, height: 44)
        self.imagePosition = .imageAbove
        self.alignment = .center
        self.font = .systemFont(ofSize: 11, weight: .regular)
        self.lineBreakMode = .byTruncatingTail
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.target = target
        self.action = action
        self.toolTip = title
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHover()
    }

    func clearHover() {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

@MainActor
final class ApplicationGridScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?()
        super.scrollWheel(with: event)
    }
}

@MainActor
final class ApplicationGridContentView: NSVisualEffectView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}

@MainActor
final class ApplicationGridPanel: NSPanel {
    private let grid = NSGridView()
    private let scrollView = ApplicationGridScrollView()
    private let filterLabel = NSTextField(labelWithString: "Type to filter apps")
    private var allApps: [URL] = []
    private var filterText = ""
    private var openURL: ((URL) -> Void)?
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        let effect = ApplicationGridContentView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.75
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.onEnter = { [weak self] in self?.onEnter?() }
        effect.onExit = { [weak self] in self?.onExit?() }

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.onScroll = { [weak self] in self?.clearHoverState() }

        filterLabel.font = .systemFont(ofSize: 12, weight: .medium)
        filterLabel.textColor = .secondaryLabelColor
        filterLabel.translatesAutoresizingMaskIntoConstraints = false

        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = grid

        effect.addSubview(filterLabel)
        effect.addSubview(scrollView)
        contentView = effect
        NSLayoutConstraint.activate([
            filterLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            filterLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            filterLabel.topAnchor.constraint(equalTo: effect.topAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: filterLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12),
            grid.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    func show(apps: [URL], relativeTo view: NSView, openURL: @escaping (URL) -> Void) {
        self.openURL = openURL
        self.allApps = apps
        filterText = ""
        rebuildGrid(resetScroll: true)
        updateFilterLabel()
        clearHoverState()

        guard let window = view.window else { return }
        let size = NSSize(width: 520, height: 360)
        setContentSize(size)
        let iconRect = window.convertToScreen(view.convert(view.bounds, to: nil))
        setFrameOrigin(NSPoint(x: iconRect.midX - size.width / 2, y: iconRect.maxY + 12))
        orderFrontRegardless()
        makeKey()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            if filterText.isEmpty {
                orderOut(nil)
            } else {
                filterText = ""
                updateFilter()
            }
        case 51, 117:
            guard !filterText.isEmpty else { return }
            filterText.removeLast()
            updateFilter()
        case 36:
            if let firstApp = filteredApps().first {
                openURL?(firstApp)
                orderOut(nil)
            }
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return }
            let filteredCharacters = characters.filter { !$0.isNewline && $0 != "\t" && $0 != "\u{1B}" }
            guard !filteredCharacters.isEmpty else { return }
            filterText.append(contentsOf: filteredCharacters)
            updateFilter()
        }
    }

    private func updateFilter() {
        rebuildGrid(resetScroll: true)
        updateFilterLabel()
        clearHoverState()
    }

    private func rebuildGrid(resetScroll: Bool) {
        grid.subviews.forEach { $0.removeFromSuperview() }

        let columns = 6
        var rows: [[NSView]] = []
        let apps = filteredApps()
        for chunkStart in stride(from: 0, to: apps.count, by: columns) {
            let chunk = apps[chunkStart..<min(chunkStart + columns, apps.count)]
            rows.append(chunk.map { url in
                let button = ApplicationButton(url: url, target: self, action: #selector(openApp(_:)))
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 74),
                    button.heightAnchor.constraint(equalToConstant: 78)
                ])
                return button
            })
        }
        if rows.isEmpty {
            rows = [[NSTextField(labelWithString: "No applications found")]]
        }

        let newGrid = NSGridView(views: rows)
        newGrid.rowSpacing = 8
        newGrid.columnSpacing = 8
        newGrid.translatesAutoresizingMaskIntoConstraints = false
        grid.addSubview(newGrid)
        NSLayoutConstraint.activate([
            newGrid.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            newGrid.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            newGrid.topAnchor.constraint(equalTo: grid.topAnchor),
            newGrid.bottomAnchor.constraint(equalTo: grid.bottomAnchor)
        ])
        if resetScroll {
            resetScrollToTop()
        }
    }

    @objc private func openApp(_ sender: ApplicationButton) {
        openURL?(sender.url)
        orderOut(nil)
    }

    private func filteredApps() -> [URL] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allApps }
        return allApps.filter {
            $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    private func updateFilterLabel() {
        filterLabel.stringValue = filterText.isEmpty ? "Type to filter apps" : "Filter: \(filterText)"
    }

    private func clearHoverState() {
        for button in applicationButtons(in: grid) {
            button.clearHover()
        }
    }

    private func applicationButtons(in view: NSView) -> [ApplicationButton] {
        var result: [ApplicationButton] = []
        if let button = view as? ApplicationButton {
            result.append(button)
        }
        for subview in view.subviews {
            result.append(contentsOf: applicationButtons(in: subview))
        }
        return result
    }

    private func resetScrollToTop() {
        grid.layoutSubtreeIfNeeded()
        let maxY = max(0, grid.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

@MainActor
final class WindowTitleContentView: NSVisualEffectView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}

@MainActor
final class WindowTitleRowButton: NSButton {
    override var isHighlighted: Bool {
        didSet {
            updateBackground(isHovering: isHighlighted)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        updateBackground(isHovering: false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        updateBackground(isHovering: true)
    }

    override func mouseExited(with event: NSEvent) {
        updateBackground(isHovering: false)
    }

    private func updateBackground(isHovering: Bool) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isHovering ? 0.13 : 0.07).cgColor
    }
}

@MainActor
final class WindowTitlePanel: NSPanel {
    private let stackView = NSStackView()
    private var items: [WindowListItem] = []
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let effect = WindowTitleContentView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderWidth = 0.75
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.onEnter = { [weak self] in self?.onEnter?() }
        effect.onExit = { [weak self] in self?.onExit?() }

        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(stackView)
        contentView = effect
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: effect.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
    }

    func show(items: [WindowListItem], relativeTo view: NSView, edge: Edge) {
        guard let window = view.window else { return }
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        self.items = Array(items.prefix(8))
        let displayedTitles = self.items.isEmpty ? ["No visible windows"] : self.items.map(\.title)
        for (index, title) in displayedTitles.enumerated() {
            stackView.addArrangedSubview(titleRow(title, index: index, isEnabled: !self.items.isEmpty))
        }

        let width = min(max(displayedTitles.map { CGFloat($0.count) * 7.0 }.max() ?? 160, 220), 420)
        let height = CGFloat(displayedTitles.count) * 30 + 16
        let size = NSSize(width: width, height: height)
        setContentSize(size)

        let iconRect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let finalOrigin: NSPoint
        switch edge {
        case .top:
            finalOrigin = NSPoint(x: iconRect.midX - size.width / 2, y: iconRect.minY - size.height - 12)
        case .left:
            finalOrigin = NSPoint(x: iconRect.maxX + 12, y: iconRect.midY - size.height / 2)
        case .right:
            finalOrigin = NSPoint(x: iconRect.minX - size.width - 12, y: iconRect.midY - size.height / 2)
        case .bottom:
            finalOrigin = NSPoint(x: iconRect.midX - size.width / 2, y: iconRect.maxY + 12)
        }
        let startOrigin = NSPoint(x: finalOrigin.x, y: finalOrigin.y - (edge == .bottom ? 8 : 0))
        setFrameOrigin(startOrigin)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(finalOrigin)
            animator().alphaValue = 1
        }
    }

    func hideAnimated() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
                self.alphaValue = 1
            }
        }
    }

    func hideImmediately() {
        orderOut(nil)
        alphaValue = 1
    }

    @objc private func openWindowRow(_ sender: WindowTitleRowButton) {
        guard items.indices.contains(sender.tag) else { return }
        items[sender.tag].open()
        hideAnimated()
    }

    private func titleRow(_ title: String, index: Int, isEnabled: Bool) -> NSView {
        let row = WindowTitleRowButton(frame: .zero)
        row.tag = index
        row.target = self
        row.action = #selector(openWindowRow(_:))
        row.isEnabled = isEnabled
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        icon.contentTintColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(icon)
        row.addSubview(label)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 26),
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 9),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -9),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }
}

final class WindowCatalog {
    static func visibleWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap { item in
            guard
                let ownerPID = item[kCGWindowOwnerPID as String] as? pid_t,
                let layer = item[kCGWindowLayer as String] as? Int,
                layer == 0,
                let boundsDict = item[kCGWindowBounds as String] as? [String: CGFloat],
                let x = boundsDict["X"],
                let y = boundsDict["Y"],
                let width = boundsDict["Width"],
                let height = boundsDict["Height"],
                width > 16,
                height > 16
            else {
                return nil
            }
            let title = item[kCGWindowName as String] as? String ?? "Window"
            return WindowInfo(ownerPID: ownerPID, title: title.isEmpty ? "Window" : title, bounds: CGRect(x: x, y: y, width: width, height: height))
        }
    }
}

final class AccessibilityWindowCatalog {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestTrustIfNeeded() {
        guard !isTrusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func windowTitles(for pid: pid_t) -> [String] {
        guard isTrusted else { return [] }
        return windows(for: pid).compactMap { window in
            windowTitle(window)
        }
    }

    static func windowItems(for pid: pid_t, appName: String, activateApp: @escaping () -> Void) -> [WindowListItem] {
        guard isTrusted else { return [] }
        let appWindows = windows(for: pid)
        return appWindows.enumerated().map { index, window in
            let title = windowTitle(window) ?? (appWindows.count == 1 ? appName : "\(appName) Window \(index + 1)")
            return WindowListItem(title: title) {
                activateApp()
                var minimizedValue: CFTypeRef?
                let isMinimized = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success
                    && (minimizedValue as? Bool == true)
                if isMinimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
        }
    }

    static func unminimizeWindows(for pid: pid_t) {
        guard isTrusted else { return }
        for window in windows(for: pid) {
            var minimizedValue: CFTypeRef?
            let isMinimized = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success
                && (minimizedValue as? Bool == true)
            if isMinimized {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
        }
    }

    private static func windows(for pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            return []
        }
        return windows
    }

    private static func windowTitle(_ window: AXUIElement) -> String? {
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
              let title = titleValue as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return title
    }
}

final class DockBadgeCatalog {
    static func badgeTexts() -> [String: String] {
        guard AccessibilityWindowCatalog.isTrusted,
              let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" })
        else {
            return [:]
        }

        var badges: [String: String] = [:]
        collectBadges(from: AXUIElementCreateApplication(dock.processIdentifier), into: &badges)
        return badges
    }

    private static func collectBadges(from element: AXUIElement, into badges: inout [String: String]) {
        if role(of: element) == "AXDockItem",
           let status = stringAttribute(element, "AXStatusLabel"),
           let badge = displayBadge(from: status),
           let bundleID = bundleIdentifier(for: element) {
            badges[bundleID] = badge
        }

        guard let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] else { return }
        for child in children {
            collectBadges(from: child, into: &badges)
        }
    }

    private static func bundleIdentifier(for element: AXUIElement) -> String? {
        guard let url = urlAttribute(element, "AXURL"), url.isFileURL else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    private static func displayBadge(from status: String) -> String? {
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let digits = trimmed.split(whereSeparator: { !$0.isNumber }).first,
           let count = Int(digits) {
            guard count > 0 else { return nil }
            return count > 99 ? "99+" : "\(count)"
        }
        return "•"
    }

    private static func role(of element: AXUIElement) -> String? {
        stringAttribute(element, kAXRoleAttribute as String)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func urlAttribute(_ element: AXUIElement, _ name: String) -> URL? {
        let value = attribute(element, name)
        if let url = value as? URL {
            return url
        }
        if let string = value as? String {
            return URL(string: string)
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

final class ApplicationCatalog {
    private(set) var urls: [URL] = []
    private var lastRefresh: Date?
    private let refreshInterval: TimeInterval = 300

    func refreshIfNeeded(force: Bool = false) {
        if !force,
           let lastRefresh,
           Date().timeIntervalSince(lastRefresh) < refreshInterval,
           !urls.isEmpty {
            return
        }
        urls = Self.discoverApplications()
        lastRefresh = Date()
    }

    private static func discoverApplications() -> [URL] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Setapp")
        ]
        var urls: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    urls.append(url)
                    enumerator.skipDescendants()
                    continue
                }

                if let values = try? url.resourceValues(forKeys: Set(keys)),
                   values.isPackage == true {
                    enumerator.skipDescendants()
                }
            }
        }
        return Array(Set(urls)).sorted {
            $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare($1.deletingPathExtension().lastPathComponent) == .orderedAscending
        }
    }
}

final class ActivitySampler {
    static func samples(for pids: [pid_t]) -> [pid_t: ProcessSample] {
        guard !pids.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=,%cpu=,rss=", "-p", pids.map(String.init).joined(separator: ",")]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        var result: [pid_t: ProcessSample] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3, let pid = pid_t(parts[0]), let rss = Int(parts[2]) else { continue }
            let mb = max(1, rss / 1024)
            result[pid] = ProcessSample(cpu: "\(parts[1])%", memory: "\(mb) MB")
        }
        return result
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum Pane: String, CaseIterable {
        case layout = "Layout"
        case appearance = "Appearance"
        case items = "Items"
        case behavior = "Behavior"
        case system = "System"
    }

    private let edgePopup = NSPopUpButton()
    private let themePopup = NSPopUpButton()
    private let rowsStepper = NSStepper()
    private let rowsValueLabel = NSTextField(labelWithString: "")
    private let barSizeSlider = NSSlider(value: 0, minValue: 54, maxValue: 180, target: nil, action: nil)
    private let barSizeValueLabel = NSTextField(labelWithString: "")
    private let iconSizeSlider = NSSlider(value: 0, minValue: 24, maxValue: 96, target: nil, action: nil)
    private let iconSizeValueLabel = NSTextField(labelWithString: "")
    private let itemSpacingSlider = NSSlider(value: 0, minValue: 0, maxValue: 32, target: nil, action: nil)
    private let itemSpacingValueLabel = NSTextField(labelWithString: "")
    private let autoHideCheckbox = NSButton(checkboxWithTitle: "Automatically hide and show mbar", target: nil, action: nil)
    private let activityCheckbox = NSButton(checkboxWithTitle: "Show CPU and memory in app labels", target: nil, action: nil)
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let showFinderCheckbox = NSButton(checkboxWithTitle: "Show Finder", target: nil, action: nil)
    private let showApplicationsCheckbox = NSButton(checkboxWithTitle: "Show Applications launcher", target: nil, action: nil)
    private let showTrashCheckbox = NSButton(checkboxWithTitle: "Show Trash", target: nil, action: nil)
    private let contentStack = NSStackView()
    private var paneButtons: [Pane: NSButton] = [:]
    private var selectedPane: Pane = .layout
    var onClose: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "mbar Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
        refreshControls()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showAndRefresh() {
        refreshControls()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = sidebarView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(sidebar)
        root.addArrangedSubview(contentStack)

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 168)
        ])
        selectPane(.layout)
    }

    private func sidebarView() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "mbar")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "Settings")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        for pane in Pane.allCases {
            let button = sidebarButton(for: pane)
            paneButtons[pane] = button
            stack.addArrangedSubview(button)
        }

        sidebar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: sidebar.bottomAnchor)
        ])
        return sidebar
    }

    private func sidebarButton(for pane: Pane) -> NSButton {
        let button = NSButton(title: pane.rawValue, target: self, action: #selector(sidebarPaneSelected(_:)))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.alignment = .left
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.tag = Pane.allCases.firstIndex(of: pane) ?? 0
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 140),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])
        return button
    }

    @objc private func sidebarPaneSelected(_ sender: NSButton) {
        guard Pane.allCases.indices.contains(sender.tag) else { return }
        selectPane(Pane.allCases[sender.tag])
    }

    private func selectPane(_ pane: Pane) {
        selectedPane = pane
        paneButtons.forEach { candidate, button in
            button.contentTintColor = candidate == pane ? .controlAccentColor : .labelColor
        }
        refreshControls()
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let title = NSTextField(labelWithString: pane.rawValue)
        title.font = .systemFont(ofSize: 26, weight: .bold)
        let subtitle = NSTextField(labelWithString: paneSubtitle(pane))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        contentStack.addArrangedSubview(title)
        contentStack.addArrangedSubview(subtitle)

        switch pane {
        case .layout:
            contentStack.addArrangedSubview(layoutSection())
        case .appearance:
            contentStack.addArrangedSubview(appearanceSection())
        case .items:
            contentStack.addArrangedSubview(itemsSection())
        case .behavior:
            contentStack.addArrangedSubview(behaviorSection())
        case .system:
            contentStack.addArrangedSubview(systemSection())
        }
    }

    private func paneSubtitle(_ pane: Pane) -> String {
        switch pane {
        case .layout:
            return "Position, density, and sizing controls for the bar."
        case .appearance:
            return "Choose the visual style mbar uses for its background."
        case .items:
            return "Choose which built-in items mbar shows alongside your apps."
        case .behavior:
            return "Interaction and information-display behavior."
        case .system:
            return "macOS permissions and helper actions."
        }
    }

    private func layoutSection() -> NSView {
        if edgePopup.numberOfItems == 0 {
            edgePopup.addItems(withTitles: Edge.allCases.map { $0.rawValue.capitalized })
        }
        edgePopup.target = self
        edgePopup.action = #selector(edgeChanged(_:))

        rowsStepper.minValue = 1
        rowsStepper.maxValue = 5
        rowsStepper.increment = 1
        rowsStepper.target = self
        rowsStepper.action = #selector(rowsChanged(_:))

        barSizeSlider.target = self
        barSizeSlider.action = #selector(barSizeChanged(_:))
        iconSizeSlider.target = self
        iconSizeSlider.action = #selector(iconSizeChanged(_:))
        itemSpacingSlider.target = self
        itemSpacingSlider.action = #selector(itemSpacingChanged(_:))

        return section(
            title: "Layout",
            detail: "The same controls Dock and uBar users expect: screen edge, density, and icon scale.",
            rows: [
                row("Position", edgePopup),
                row("Rows", pair(rowsStepper, rowsValueLabel)),
                row("Bar size", pair(barSizeSlider, barSizeValueLabel)),
                row("Icon size", pair(iconSizeSlider, iconSizeValueLabel)),
                row("Item spacing", pair(itemSpacingSlider, itemSpacingValueLabel))
            ]
        )
    }

    private func appearanceSection() -> NSView {
        if themePopup.numberOfItems == 0 {
            themePopup.addItems(withTitles: BarTheme.allCases.map(\.displayName))
        }
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))

        return section(
            title: "Theme",
            detail: "Default keeps mbar's current compact HUD style. macOS Glass uses a brighter translucent material to feel closer to the native Dock.",
            rows: [
                row("Theme", themePopup)
            ]
        )
    }

    private func behaviorSection() -> NSView {
        autoHideCheckbox.target = self
        autoHideCheckbox.action = #selector(autoHideChanged(_:))
        activityCheckbox.target = self
        activityCheckbox.action = #selector(activityModeChanged(_:))
        return section(
            title: "Behavior",
            detail: "Control when mbar hides and how much app detail it shows.",
            rows: [
                fullWidth(autoHideCheckbox),
                fullWidth(activityCheckbox),
                infoRow("Display mode", "All apps on every display")
            ]
        )
    }

    private func itemsSection() -> NSView {
        showFinderCheckbox.target = self
        showFinderCheckbox.action = #selector(specialItemVisibilityChanged(_:))
        showApplicationsCheckbox.target = self
        showApplicationsCheckbox.action = #selector(specialItemVisibilityChanged(_:))
        showTrashCheckbox.target = self
        showTrashCheckbox.action = #selector(specialItemVisibilityChanged(_:))

        return section(
            title: "Built-in Items",
            detail: "Finder stays hidden by default, but you can show it if you want a fuller Dock-style strip.",
            rows: [
                fullWidth(showFinderCheckbox),
                fullWidth(showApplicationsCheckbox),
                fullWidth(showTrashCheckbox)
            ]
        )
    }

    private func systemSection() -> NSView {
        let accessibilityButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings(_:)))
        let dockSettingsButton = NSButton(title: "Open Desktop & Dock Settings", target: self, action: #selector(openDockSettings(_:)))
        let hideDockButton = NSButton(title: "Hide Native Dock", target: self, action: #selector(hideNativeDock(_:)))
        let resetButton = NSButton(title: "Reset Layout Defaults", target: self, action: #selector(resetLayoutDefaults(_:)))

        return section(
            title: "System",
            detail: "Accessibility powers real window titles, window selection, and Dock badge labels.",
            rows: [
                row("Accessibility", accessibilityStatusLabel),
                fullWidth(accessibilityButton),
                fullWidth(dockSettingsButton),
                fullWidth(hideDockButton),
                fullWidth(resetButton)
            ]
        )
    }

    private func section(title: String, detail: String, rows: [NSView]) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 14
        box.borderWidth = 0.75
        box.borderColor = NSColor.separatorColor.withAlphaComponent(0.7)
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(detailLabel)
        for row in rows {
            stack.addArrangedSubview(row)
        }

        box.contentView = NSView()
        box.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 496),
            stack.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor)
        ])
        return box
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 468),
            label.widthAnchor.constraint(equalToConstant: 126)
        ])
        return stack
    }

    private func infoRow(_ title: String, _ value: String) -> NSView {
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.textColor = .secondaryLabelColor
        return row(title, valueLabel)
    }

    private func fullWidth(_ view: NSView) -> NSView {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(lessThanOrEqualToConstant: 444)
        ])
        return view
    }

    private func pair(_ first: NSView, _ second: NSView) -> NSView {
        let stack = NSStackView(views: [first, second])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            first.widthAnchor.constraint(equalToConstant: first is NSSlider ? 205 : 70),
            second.widthAnchor.constraint(equalToConstant: 52)
        ])
        return stack
    }

    private func refreshControls() {
        edgePopup.selectItem(withTitle: Settings.edge.rawValue.capitalized)
        rowsStepper.integerValue = Settings.rows
        rowsValueLabel.stringValue = "\(Settings.rows)"
        barSizeSlider.doubleValue = Double(Settings.barSize)
        barSizeValueLabel.stringValue = "\(Int(Settings.barSize)) px"
        iconSizeSlider.doubleValue = Double(Settings.iconSize)
        iconSizeValueLabel.stringValue = "\(Int(Settings.iconSize)) px"
        itemSpacingSlider.doubleValue = Double(Settings.itemSpacing)
        itemSpacingValueLabel.stringValue = "\(Int(Settings.itemSpacing)) px"
        themePopup.selectItem(withTitle: Settings.theme.displayName)
        autoHideCheckbox.state = Settings.autoHide ? .on : .off
        activityCheckbox.state = Settings.activityMode ? .on : .off
        showFinderCheckbox.state = Settings.showFinder ? .on : .off
        showApplicationsCheckbox.state = Settings.showApplications ? .on : .off
        showTrashCheckbox.state = Settings.showTrash ? .on : .off
        accessibilityStatusLabel.stringValue = AccessibilityWindowCatalog.isTrusted ? "Granted" : "Not granted"
        accessibilityStatusLabel.textColor = AccessibilityWindowCatalog.isTrusted ? .systemGreen : .systemOrange
    }

    @objc private func edgeChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title.lowercased(), let edge = Edge(rawValue: title) else { return }
        Settings.edge = edge
        AppDelegate.shared?.rebuildBars()
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard let index = BarTheme.allCases.firstIndex(where: { $0.displayName == sender.selectedItem?.title }) else { return }
        Settings.theme = BarTheme.allCases[index]
        refreshControls()
        AppDelegate.shared?.refreshBarTheme()
    }

    @objc private func rowsChanged(_ sender: NSStepper) {
        Settings.rows = sender.integerValue
        refreshControls()
        AppDelegate.shared?.refreshBarLayout()
    }

    @objc private func barSizeChanged(_ sender: NSSlider) {
        Settings.barSize = CGFloat(sender.doubleValue)
        refreshControls()
        AppDelegate.shared?.refreshBarLayout()
    }

    @objc private func iconSizeChanged(_ sender: NSSlider) {
        Settings.iconSize = CGFloat(sender.doubleValue)
        refreshControls()
        AppDelegate.shared?.refreshBarLayout()
    }

    @objc private func itemSpacingChanged(_ sender: NSSlider) {
        Settings.itemSpacing = CGFloat(sender.doubleValue)
        refreshControls()
        AppDelegate.shared?.refreshBarLayout()
    }

    @objc private func autoHideChanged(_ sender: NSButton) {
        Settings.autoHide = sender.state == .on
        refreshControls()
        AppDelegate.shared?.applyAutoHidePreference()
    }

    @objc private func activityModeChanged(_ sender: NSButton) {
        Settings.activityMode = sender.state == .on
        refreshControls()
        AppDelegate.shared?.rebuildBarsInPlace()
    }

    @objc private func specialItemVisibilityChanged(_ sender: NSButton) {
        Settings.showFinder = showFinderCheckbox.state == .on
        Settings.showApplications = showApplicationsCheckbox.state == .on
        Settings.showTrash = showTrashCheckbox.state == .on
        refreshControls()
        AppDelegate.shared?.rebuildBars()
    }

    @objc private func openAccessibilitySettings(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openDockSettings(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }

    @objc private func hideNativeDock(_ sender: NSButton) {
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-time-modifier", "-float", "0"])
        run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/com.apple.Dock.agent"])
    }

    @objc private func resetLayoutDefaults(_ sender: NSButton) {
        Settings.edge = .bottom
        Settings.rows = 1
        Settings.barSize = 78
        Settings.iconSize = 42
        Settings.itemSpacing = 9
        refreshControls()
        AppDelegate.shared?.rebuildBars()
    }

    private func run(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try? process.run()
    }
}

@MainActor
final class TaskbarIconCell: NSButtonCell {
    override func imageRect(forBounds rect: NSRect) -> NSRect {
        let size = min(Settings.iconSize, rect.width, rect.height)
        return NSRect(
            x: rect.midX - size / 2,
            y: rect.midY - size / 2,
            width: size,
            height: size
        )
    }
}

@MainActor
final class TaskbarItemView: NSButton, NSDraggingSource {
    let representedBundleID: String?
    let representedPID: pid_t?
    private let displayTitle: String
    private let activeIndicator = CALayer()
    private let badgeView = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let showsActiveIndicator: Bool
    private let showsRunningIndicator: Bool
    private let badgeText: String?
    private var mouseDownEvent: NSEvent?
    var onDragStarted: (() -> Void)?
    var onDragFinished: ((String, Bool) -> Void)?
    var onHoverStarted: ((TaskbarItemView) -> Void)?
    var onHoverEnded: (() -> Void)?

    init(title: String, image: NSImage?, bundleID: String?, pid: pid_t?, isActive: Bool = false, isRunning: Bool = false, isHidden: Bool = false, attention: Bool = false, badgeText: String? = nil, target: AnyObject?, action: Selector?) {
        self.representedBundleID = bundleID
        self.representedPID = pid
        self.displayTitle = title
        self.showsActiveIndicator = isActive
        self.showsRunningIndicator = isRunning || isActive
        self.badgeText = badgeText
        super.init(frame: .zero)
        self.cell = TaskbarIconCell()
        self.title = ""
        self.image = image
        self.imagePosition = .imageOnly
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.target = target
        self.action = action
        self.setButtonType(.momentaryPushIn)
        self.toolTip = title
        self.imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 8
        layer?.shadowOffset = NSSize(width: 0, height: 3)
        contentTintColor = isHidden ? .tertiaryLabelColor : nil

        activeIndicator.backgroundColor = (isActive ? NSColor.controlAccentColor : NSColor.secondaryLabelColor.withAlphaComponent(0.55)).cgColor
        activeIndicator.cornerRadius = 2
        activeIndicator.isHidden = !showsRunningIndicator
        layer?.addSublayer(activeIndicator)

        badgeView.wantsLayer = true
        badgeView.layer?.backgroundColor = NSColor.systemRed.cgColor
        badgeView.layer?.borderColor = NSColor.windowBackgroundColor.cgColor
        badgeView.layer?.borderWidth = 1.5
        badgeView.layer?.cornerRadius = 9
        badgeView.layer?.cornerCurve = .continuous
        badgeView.layer?.shadowColor = NSColor.black.cgColor
        badgeView.layer?.shadowOpacity = 0.18
        badgeView.layer?.shadowRadius = 4
        badgeView.layer?.shadowOffset = NSSize(width: 0, height: 1)
        badgeView.isHidden = badgeText == nil
        badgeView.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.stringValue = badgeText ?? ""
        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)
        addSubview(badgeView, positioned: .above, relativeTo: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        animateTile(scale: 1.04, yOffset: 1, shadowOpacity: 0.10)
        onHoverStarted?(self)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        animateTile(scale: 1.0, yOffset: 0, shadowOpacity: 0)
        onHoverEnded?()
    }

    override var isHighlighted: Bool {
        didSet {
            animateTile(scale: isHighlighted ? 0.98 : 1.0, yOffset: 0, shadowOpacity: isHighlighted ? 0.06 : 0)
        }
    }

    override func layout() {
        super.layout()
        let length: CGFloat = showsActiveIndicator ? 18 : 7
        let thickness: CGFloat = showsActiveIndicator ? 4 : 3
        activeIndicator.cornerRadius = thickness / 2
        switch Settings.edge {
        case .bottom:
            activeIndicator.frame = CGRect(x: (bounds.width - length) / 2, y: 2, width: length, height: thickness)
        case .top:
            activeIndicator.frame = CGRect(x: (bounds.width - length) / 2, y: bounds.maxY - thickness - 2, width: length, height: thickness)
        case .left:
            activeIndicator.frame = CGRect(x: 2, y: (bounds.height - length) / 2, width: thickness, height: length)
        case .right:
            activeIndicator.frame = CGRect(x: bounds.maxX - thickness - 2, y: (bounds.height - length) / 2, width: thickness, height: length)
        }
        let badgeWidth: CGFloat = badgeText.map { $0.count > 1 ? 24 : 18 } ?? 18
        let badgeY = isFlipped ? 3 : bounds.maxY - 15
        badgeView.frame = CGRect(x: bounds.maxX - badgeWidth - 3, y: badgeY, width: badgeWidth, height: 18)
        badgeLabel.frame = badgeView.bounds.insetBy(dx: 2, dy: 2)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 15, cornerHeight: 15, transform: nil)
    }

    private func animateTile(scale: CGFloat, yOffset: CGFloat, shadowOpacity: Float) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            var transform = CATransform3DMakeTranslation(0, yOffset, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            animator().layer?.transform = transform
            animator().layer?.shadowOpacity = shadowOpacity
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard representedBundleID != nil else {
            super.mouseDown(with: event)
            return
        }

        mouseDownEvent = event
        let start = convert(event.locationInWindow, from: nil)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch next.type {
            case .leftMouseDragged:
                let current = convert(next.locationInWindow, from: nil)
                if hypot(current.x - start.x, current.y - start.y) > 3 {
                    startDragging(with: next)
                    mouseDownEvent = nil
                    return
                }
            case .leftMouseUp:
                mouseDownEvent = nil
                performClick(nil)
                return
            default:
                break
            }
        }
        mouseDownEvent = nil
    }

    private func startDragging(with event: NSEvent) {
        guard let representedBundleID else {
            return
        }

        onDragStarted?()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(representedBundleID, forType: appDragPasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = image ?? NSImage(size: NSSize(width: 48, height: 48))
        let dragFrame = bounds.insetBy(dx: 8, dy: 8)
        item.setDraggingFrame(dragFrame, contents: image)

        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let representedBundleID else { return }
        let droppedInsideBar = window?.frame.contains(screenPoint) ?? false
        onDragFinished?(representedBundleID, droppedInsideBar)
    }
}

@MainActor
final class TaskbarPanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TaskbarController: NSObject, NSMenuDelegate {
    let screen: NSScreen
    let panel: TaskbarPanel
    let triggerPanel: TaskbarPanel
    let stackView = NSStackView()
    private let hoverView = HoverView()
    private let triggerView = HoverView()
    private let dockBackground = DockBackgroundView()
    private let applicationGridPanel = ApplicationGridPanel()
    private let windowTitlePanel = WindowTitlePanel()
    private var runningApps: [String: NSRunningApplication] = [:]
    private var appWindows: [pid_t: [WindowInfo]] = [:]
    private var activitySamples: [pid_t: ProcessSample] = [:]
    private var dockBadges: [String: String] = [:]
    private var hideWorkItem: DispatchWorkItem?
    private var isRevealed = false
    private var isDraggingIcon = false
    private var isBarMenuOpen = false
    private var draggedBundleID: String?
    private var liveDropIndex: Int?
    private var insertionMarker: NSView?
    private var currentAppOrder: [String] = []
    private var acceptedDropBundleIDs = Set<String>()
    private var hoverWindowWorkItem: DispatchWorkItem?
    private var windowTitleHideWorkItem: DispatchWorkItem?
    private var windowTitleSourceIconFrame: NSRect = .null
    private var isMouseInWindowTitlePanel = false

    init(screen: NSScreen) {
        self.screen = screen
        self.panel = TaskbarPanel(frame: TaskbarController.frame(for: screen))
        self.triggerPanel = TaskbarPanel(frame: TaskbarController.triggerFrame(for: screen))
        super.init()
        buildChrome()
        buildTrigger()
    }

    static func frame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let size = Settings.barSize * CGFloat(Settings.rows)
        switch Settings.edge {
        case .bottom:
            return NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: size)
        case .top:
            return NSRect(x: visible.minX, y: visible.maxY - size, width: visible.width, height: size)
        case .left:
            return NSRect(x: visible.minX, y: visible.minY, width: size, height: visible.height)
        case .right:
            return NSRect(x: visible.maxX - size, y: visible.minY, width: size, height: visible.height)
        }
    }

    static func hiddenFrame(for screen: NSScreen) -> NSRect {
        var frame = Self.frame(for: screen)
        let revealSliver: CGFloat = 2
        switch Settings.edge {
        case .bottom:
            frame.origin.y = screen.frame.minY - frame.height + revealSliver
        case .top:
            frame.origin.y = screen.frame.maxY - revealSliver
        case .left:
            frame.origin.x = screen.frame.minX - frame.width + revealSliver
        case .right:
            frame.origin.x = screen.frame.maxX - revealSliver
        }
        return frame
    }

    static func triggerFrame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let thickness: CGFloat = 6
        switch Settings.edge {
        case .bottom:
            return NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: thickness)
        case .top:
            return NSRect(x: visible.minX, y: visible.maxY - thickness, width: visible.width, height: thickness)
        case .left:
            return NSRect(x: visible.minX, y: visible.minY, width: thickness, height: visible.height)
        case .right:
            return NSRect(x: visible.maxX - thickness, y: visible.minY, width: thickness, height: visible.height)
        }
    }

    func show() {
        triggerPanel.orderFrontRegardless()
        if Settings.autoHide {
            hide(animated: false)
        } else {
            reveal()
        }
    }

    func rebuild() {
        let wasVisible = panel.isVisible
        panel.setFrame(wasVisible ? Self.frame(for: screen) : Self.hiddenFrame(for: screen), display: true, animate: false)
        triggerPanel.setFrame(Self.triggerFrame(for: screen), display: true, animate: false)
        stackView.orientation = Settings.edge == .left || Settings.edge == .right ? .vertical : .horizontal
        let windows = WindowCatalog.visibleWindows()
        appWindows = Dictionary(grouping: windows, by: \.ownerPID)
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && app.bundleIdentifier != Bundle.main.bundleIdentifier
                    && (Settings.showFinder || app.bundleIdentifier != finderBundleID)
            }

        runningApps = Dictionary(uniqueKeysWithValues: apps.compactMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return (bundleID, app)
        })
        dockBadges = DockBadgeCatalog.badgeTexts()

        if Settings.activityMode {
            activitySamples = ActivitySampler.samples(for: apps.map(\.processIdentifier))
        } else {
            activitySamples = [:]
        }

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let pinnedIDs = Settings.pinnedBundleIDs.filter { Settings.showFinder || $0 != finderBundleID }
        var renderedBundleIDs = Set<String>()
        var renderedPIDs = Set<pid_t>()
        var rebuiltAppOrder: [String] = []
        for bundleID in pinnedIDs {
            addPinnedItem(bundleID: bundleID)
            rebuiltAppOrder.append(bundleID)
            renderedBundleIDs.insert(bundleID)
            if let pid = runningApps[bundleID]?.processIdentifier {
                renderedPIDs.insert(pid)
            }
        }

        for app in apps.sorted(by: appSort) {
            guard shouldShow(app: app), !renderedPIDs.contains(app.processIdentifier) else { continue }
            if let bundleID = app.bundleIdentifier, renderedBundleIDs.contains(bundleID) {
                continue
            }
            addAppItem(app)
            renderedPIDs.insert(app.processIdentifier)
            if let bundleID = app.bundleIdentifier {
                renderedBundleIDs.insert(bundleID)
                rebuiltAppOrder.append(bundleID)
            }
        }
        currentAppOrder = rebuiltAppOrder

        if Settings.showApplications || Settings.showTrash {
            addSeparator()
        }
        if Settings.showApplications {
            addStartButton()
        }
        if Settings.showTrash {
            addTrashButton()
        }
        if wasVisible || isDraggingIcon {
            panel.orderFrontRegardless()
            panel.alphaValue = 1
            isRevealed = true
        }
    }

    func refreshLayout(preserveVisibility: Bool = true) {
        let wasVisible = panel.isVisible || isRevealed
        panel.setFrame(wasVisible || !Settings.autoHide ? Self.frame(for: screen) : Self.hiddenFrame(for: screen), display: true, animate: false)
        triggerPanel.setFrame(Self.triggerFrame(for: screen), display: true, animate: false)
        applyTheme()
        stackView.orientation = Settings.edge == .left || Settings.edge == .right ? .vertical : .horizontal
        stackView.spacing = Settings.itemSpacing
        rebuild()
        stackView.needsDisplay = true
        stackView.arrangedSubviews.forEach { $0.needsDisplay = true }
        if !Settings.autoHide || (preserveVisibility && wasVisible) {
            reveal()
        }
    }

    private func buildChrome() {
        dockBackground.blendingMode = .behindWindow
        dockBackground.state = .active
        dockBackground.translatesAutoresizingMaskIntoConstraints = false
        dockBackground.wantsLayer = true
        dockBackground.layer?.cornerCurve = .continuous
        applyTheme()
        dockBackground.onDropBundleID = { [weak self] bundleID, point in
            guard let self else { return false }
            return self.drop(bundleID: bundleID, at: self.hoverView.convert(point, from: self.dockBackground))
        }
        dockBackground.onDragBundleID = { [weak self] bundleID, point in
            guard let self else { return }
            self.updateLiveDrop(bundleID: bundleID, at: self.hoverView.convert(point, from: self.dockBackground))
        }
        dockBackground.onMenu = { [weak self] in
            self?.barContextMenu() ?? NSMenu()
        }
        windowTitlePanel.onEnter = { [weak self] in
            self?.isMouseInWindowTitlePanel = true
            self?.windowTitleHideWorkItem?.cancel()
            self?.hideWorkItem?.cancel()
            self?.reveal()
        }
        windowTitlePanel.onExit = { [weak self] in
            self?.isMouseInWindowTitlePanel = false
            self?.scheduleWindowTitleHide()
            self?.scheduleHide()
        }
        applicationGridPanel.onEnter = { [weak self] in
            self?.hideWorkItem?.cancel()
            self?.reveal()
        }
        applicationGridPanel.onExit = { [weak self] in
            self?.scheduleHide()
        }

        stackView.orientation = Settings.edge == .left || Settings.edge == .right ? .vertical : .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .gravityAreas
        stackView.spacing = Settings.itemSpacing
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        hoverView.onEnter = { [weak self] in self?.reveal() }
        hoverView.onExit = { [weak self] in self?.scheduleHide() }
        hoverView.onDropBundleID = { [weak self] bundleID, point in
            self?.drop(bundleID: bundleID, at: point) ?? false
        }
        hoverView.onDragBundleID = { [weak self] bundleID, point in
            self?.updateLiveDrop(bundleID: bundleID, at: point)
        }
        hoverView.onMenu = { [weak self] in
            self?.barContextMenu() ?? NSMenu()
        }
        hoverView.translatesAutoresizingMaskIntoConstraints = false
        hoverView.wantsLayer = true
        hoverView.layer?.backgroundColor = NSColor.clear.cgColor
        hoverView.addSubview(dockBackground)
        hoverView.addSubview(stackView, positioned: .above, relativeTo: dockBackground)
        panel.contentView = hoverView

        NSLayoutConstraint.activate([
            dockBackground.centerXAnchor.constraint(equalTo: hoverView.centerXAnchor),
            dockBackground.centerYAnchor.constraint(equalTo: hoverView.centerYAnchor),
            dockBackground.leadingAnchor.constraint(greaterThanOrEqualTo: hoverView.leadingAnchor, constant: 10),
            dockBackground.trailingAnchor.constraint(lessThanOrEqualTo: hoverView.trailingAnchor, constant: -10),
            dockBackground.topAnchor.constraint(greaterThanOrEqualTo: hoverView.topAnchor, constant: 5),
            dockBackground.bottomAnchor.constraint(lessThanOrEqualTo: hoverView.bottomAnchor, constant: -5),
            stackView.leadingAnchor.constraint(equalTo: dockBackground.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: dockBackground.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: dockBackground.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: dockBackground.bottomAnchor)
        ])
    }

    private func buildTrigger() {
        triggerView.onEnter = { [weak self] in self?.reveal() }
        triggerView.onExit = { [weak self] in self?.scheduleHide() }
        triggerView.wantsLayer = true
        triggerView.layer?.backgroundColor = NSColor.clear.cgColor
        triggerPanel.contentView = triggerView
        triggerPanel.hasShadow = false
        triggerPanel.alphaValue = 0.01
    }

    private func applyTheme() {
        dockBackground.wantsLayer = true
        dockBackground.layer?.shadowColor = NSColor.black.cgColor
        dockBackground.layer?.cornerCurve = .continuous
        switch Settings.theme {
        case .default:
            dockBackground.alphaValue = 1
            dockBackground.blendingMode = .behindWindow
            dockBackground.material = .hudWindow
            dockBackground.layer?.cornerRadius = 22
            dockBackground.layer?.borderWidth = 0.75
            dockBackground.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
            dockBackground.layer?.backgroundColor = NSColor.clear.cgColor
            dockBackground.layer?.shadowOpacity = 0.28
            dockBackground.layer?.shadowRadius = 22
            dockBackground.layer?.shadowOffset = NSSize(width: 0, height: 8)
            dockBackground.applyGlassOverlays(enabled: false, cornerRadius: 22)
        case .macOSGlass:
            dockBackground.alphaValue = 0.58
            dockBackground.blendingMode = .behindWindow
            dockBackground.material = .underPageBackground
            dockBackground.layer?.cornerRadius = 32
            dockBackground.layer?.borderWidth = 0
            dockBackground.layer?.borderColor = nil
            dockBackground.layer?.backgroundColor = NSColor.clear.cgColor
            dockBackground.layer?.shadowColor = NSColor.black.cgColor
            dockBackground.layer?.shadowOpacity = 0.22
            dockBackground.layer?.shadowRadius = 26
            dockBackground.layer?.shadowOffset = NSSize(width: 0, height: 8)
            dockBackground.applyGlassOverlays(enabled: true, cornerRadius: 32)
        }
        dockBackground.needsDisplay = true
        dockBackground.needsLayout = true
        dockBackground.layer?.setNeedsDisplay()
    }

    func refreshTheme() {
        applyTheme()
        panel.contentView?.needsDisplay = true
        panel.contentView?.needsLayout = true
        panel.invalidateShadow()
    }

    func reveal() {
        hideWorkItem?.cancel()
        guard !isRevealed else { return }
        isRevealed = true
        panel.setFrame(Self.hiddenFrame(for: screen), display: false, animate: false)
        panel.alphaValue = 0.98
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(Self.frame(for: screen), display: true)
            panel.animator().alphaValue = 1
        }
    }

    func scheduleHide() {
        hideWorkItem?.cancel()
        guard Settings.autoHide else { return }
        guard !isDraggingIcon, !isBarMenuOpen else { return }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard Settings.autoHide else { return }
                guard !self.isDraggingIcon, !self.isBarMenuOpen else { return }
                guard AppDelegate.shared?.isSettingsVisible != true else { return }
                let mouse = NSEvent.mouseLocation
                if self.keepAliveFrame().contains(mouse)
                    || self.triggerPanel.frame.contains(mouse)
                    || self.applicationGridKeepAliveFrame().contains(mouse)
                    || self.windowTitleKeepAliveFrame().contains(mouse) {
                    self.scheduleHide()
                } else {
                    self.hide(animated: true)
                }
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }

    private func keepAliveFrame() -> NSRect {
        let inset: CGFloat = isDraggingIcon ? -180 : -18
        let verticalInset: CGFloat = isDraggingIcon ? -140 : -28
        return panel.frame.insetBy(dx: inset, dy: verticalInset)
    }

    private func windowTitleKeepAliveFrame() -> NSRect {
        guard windowTitlePanel.isVisible else { return .null }
        let sourceFrame = windowTitleSourceIconFrame.insetBy(dx: -12, dy: -12)
        guard isMouseInWindowTitlePanel else { return sourceFrame }
        return windowTitlePanel.frame.insetBy(dx: -18, dy: -18).union(sourceFrame)
    }

    private func applicationGridKeepAliveFrame() -> NSRect {
        guard applicationGridPanel.isVisible else { return .null }
        return applicationGridPanel.frame.insetBy(dx: -18, dy: -18).union(panel.frame.insetBy(dx: -24, dy: -32))
    }

    private func hide(animated: Bool) {
        hideWorkItem?.cancel()
        guard Settings.autoHide else {
            reveal()
            return
        }
        isRevealed = false
        applicationGridPanel.orderOut(nil)
        hideWindowTitlePanel(animated: false)
        guard panel.isVisible else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(Self.hiddenFrame(for: screen), display: true)
                panel.animator().alphaValue = 0.98
            } completionHandler: {
                Task { @MainActor in
                    self.panel.orderOut(nil)
                    self.panel.alphaValue = 1
                    self.panel.setFrame(Self.hiddenFrame(for: self.screen), display: false, animate: false)
                }
            }
        } else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.setFrame(Self.hiddenFrame(for: screen), display: false, animate: false)
        }
    }

    func hideForExternalInteraction(at screenPoint: NSPoint? = nil) {
        guard Settings.autoHide else { return }
        guard !isDraggingIcon, !isBarMenuOpen else { return }
        guard AppDelegate.shared?.isSettingsVisible != true else { return }
        guard screenPoint != nil || !applicationGridPanel.isVisible else { return }
        if let screenPoint,
           keepAliveFrame().contains(screenPoint)
            || applicationGridPanel.frame.contains(screenPoint)
            || applicationGridKeepAliveFrame().contains(screenPoint)
            || windowTitleKeepAliveFrame().contains(screenPoint) {
            return
        }
        hide(animated: true)
    }

    private func addStartButton() {
        let image = NSWorkspace.shared.icon(forFile: "/Applications")
        image.size = NSSize(width: Settings.iconSize, height: Settings.iconSize)
        let button = TaskbarItemView(title: "Applications", image: image, bundleID: nil, pid: nil, isActive: false, target: self, action: #selector(openStartMenu(_:)))
        constrain(button)
        stackView.addArrangedSubview(button)
    }

    private func addPinnedItem(bundleID: String) {
        guard Settings.showFinder || bundleID != finderBundleID else { return }
        if let app = runningApps[bundleID] {
            addAppItem(app)
            return
        }

        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let title = url?.deletingPathExtension().lastPathComponent ?? bundleID
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: title)
        icon?.size = NSSize(width: Settings.iconSize, height: Settings.iconSize)
        let button = TaskbarItemView(title: title, image: icon, bundleID: bundleID, pid: nil, isActive: false, target: self, action: #selector(launchPinned(_:)))
        button.menu = pinnedMenu(bundleID: bundleID)
        button.onDragStarted = { [weak self] in
            self?.startIconDrag(bundleID: bundleID)
            self?.hideWorkItem?.cancel()
        }
        button.onDragFinished = { [weak self] bundleID, droppedInsideBar in
            self?.dragFinished(bundleID: bundleID, droppedInsideBar: droppedInsideBar)
        }
        constrain(button)
        stackView.addArrangedSubview(button)
    }

    private func addAppItem(_ app: NSRunningApplication) {
        let title = titleFor(app)
        let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: title)
        icon?.size = NSSize(width: Settings.iconSize, height: Settings.iconSize)
        let badge = badgeText(for: app)
        let button = TaskbarItemView(title: title, image: icon, bundleID: app.bundleIdentifier, pid: app.processIdentifier, isActive: app.isActive, isRunning: true, isHidden: app.isHidden, attention: false, badgeText: badge, target: self, action: #selector(activateApp(_:)))
        button.menu = appMenu(app)
        button.onDragStarted = { [weak self] in
            if let bundleID = app.bundleIdentifier {
                self?.startIconDrag(bundleID: bundleID)
            }
            self?.hideWorkItem?.cancel()
        }
        button.onDragFinished = { [weak self] bundleID, droppedInsideBar in
            self?.dragFinished(bundleID: bundleID, droppedInsideBar: droppedInsideBar)
        }
        button.onHoverStarted = { [weak self, weak app] button in
            guard let app else { return }
            self?.scheduleWindowTitlePanel(for: app, relativeTo: button)
        }
        button.onHoverEnded = { [weak self] in
            self?.scheduleWindowTitleHide()
        }
        constrain(button)
        stackView.addArrangedSubview(button)
    }

    private func scheduleWindowTitlePanel(for app: NSRunningApplication, relativeTo button: TaskbarItemView) {
        hoverWindowWorkItem?.cancel()
        windowTitleHideWorkItem?.cancel()
        if windowTitlePanel.isVisible {
            windowTitlePanel.hideImmediately()
            windowTitleSourceIconFrame = .null
            isMouseInWindowTitlePanel = false
        }
        guard !isDraggingIcon else { return }
        let item = DispatchWorkItem { [weak self, weak button, weak app] in
            Task { @MainActor in
                guard let self, self.isRevealed, let button, let app, let window = button.window else { return }
                let items = self.windowListItems(for: app)
                guard items.count > 1 else { return }
                self.windowTitleSourceIconFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
                self.isMouseInWindowTitlePanel = false
                self.windowTitlePanel.show(items: items, relativeTo: button, edge: Settings.edge)
            }
        }
        hoverWindowWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: item)
    }

    private func hideWindowTitlePanel(animated: Bool = true) {
        hoverWindowWorkItem?.cancel()
        windowTitleHideWorkItem?.cancel()
        hoverWindowWorkItem = nil
        windowTitleHideWorkItem = nil
        windowTitleSourceIconFrame = .null
        isMouseInWindowTitlePanel = false
        if animated {
            windowTitlePanel.hideAnimated()
        } else {
            windowTitlePanel.hideImmediately()
        }
    }

    private func scheduleWindowTitleHide() {
        hoverWindowWorkItem?.cancel()
        windowTitleHideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let mouse = NSEvent.mouseLocation
                if self.windowTitleKeepAliveFrame().contains(mouse) {
                    self.scheduleWindowTitleHide()
                } else {
                    self.hideWindowTitlePanel()
                }
            }
        }
        windowTitleHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: item)
    }

    private func startIconDrag(bundleID: String) {
        guard Settings.showFinder || bundleID != finderBundleID else { return }
        hideWindowTitlePanel()
        isDraggingIcon = true
        draggedBundleID = bundleID
        liveDropIndex = nil
        setDraggedIconHidden(true)
        reveal()
    }

    private func drop(bundleID: String, at point: CGPoint) -> Bool {
        guard Settings.showFinder || bundleID != finderBundleID else { return false }
        guard runningApps[bundleID] != nil || NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            return false
        }

        var pins = currentAppOrder.filter { $0 != bundleID && (Settings.showFinder || $0 != finderBundleID) }
        let insertionIndex = appInsertionIndex(forDrop: point, excluding: bundleID)
        pins.insert(bundleID, at: min(insertionIndex, pins.count))
        acceptedDropBundleIDs.insert(bundleID)
        Settings.pinnedBundleIDs = pins
        AppDelegate.shared?.rebuildBarsInPlace()
        return true
    }

    private func updateLiveDrop(bundleID: String, at point: CGPoint) {
        guard isDraggingIcon, Settings.showFinder || bundleID != finderBundleID else { return }
        let newIndex = appInsertionIndex(forDrop: point, excluding: bundleID)
        guard liveDropIndex != newIndex else { return }
        liveDropIndex = newIndex
        moveInsertionMarker(toAppSlot: newIndex)
    }

    private func moveInsertionMarker(toAppSlot appSlot: Int) {
        let marker = insertionMarker ?? makeInsertionMarker()
        insertionMarker = marker
        if marker.superview != nil {
            stackView.removeArrangedSubview(marker)
            marker.removeFromSuperview()
        }

        let arrangedIndex = arrangedSubviewIndex(forAppSlot: appSlot)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.06
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            stackView.insertArrangedSubview(marker, at: arrangedIndex)
            stackView.layoutSubtreeIfNeeded()
        }
    }

    private func makeInsertionMarker() -> NSView {
        let marker = NSView()
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.wantsLayer = true
        marker.layer?.cornerRadius = 2
        marker.layer?.cornerCurve = .continuous
        marker.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        if Settings.edge == .left || Settings.edge == .right {
            NSLayoutConstraint.activate([
                marker.widthAnchor.constraint(equalToConstant: Settings.barSize - 28),
                marker.heightAnchor.constraint(equalToConstant: 4)
            ])
        } else {
            NSLayoutConstraint.activate([
                marker.widthAnchor.constraint(equalToConstant: 4),
                marker.heightAnchor.constraint(equalToConstant: Settings.barSize - 28)
            ])
        }
        return marker
    }

    private func arrangedSubviewIndex(forAppSlot appSlot: Int) -> Int {
        var appIndex = 0
        for (arrangedIndex, view) in stackView.arrangedSubviews.enumerated() {
            if view === insertionMarker { continue }
            guard let item = view as? TaskbarItemView, item.representedBundleID != nil else {
                return arrangedIndex
            }
            if item.representedBundleID == draggedBundleID { continue }
            if appIndex == appSlot {
                return arrangedIndex
            }
            appIndex += 1
        }
        return stackView.arrangedSubviews.count
    }

    private func appInsertionIndex(forDrop point: CGPoint, excluding bundleID: String) -> Int {
        let stackPoint = stackView.convert(point, from: hoverView)
        let isVertical = Settings.edge == .left || Settings.edge == .right
        let dropPosition = isVertical ? stackPoint.y : stackPoint.x
        var index = 0
        for view in stackView.arrangedSubviews {
            guard let item = view as? TaskbarItemView, let itemBundleID = item.representedBundleID else { continue }
            if itemBundleID == bundleID { continue }
            let itemMid = isVertical ? item.frame.midY : item.frame.midX
            if dropPosition > itemMid {
                index += 1
            }
        }
        return index
    }

    private func dragFinished(bundleID: String, droppedInsideBar: Bool) {
        isDraggingIcon = false
        draggedBundleID = nil
        liveDropIndex = nil
        removeInsertionMarker()
        setDraggedIconHidden(false)
        let wasAcceptedDrop = acceptedDropBundleIDs.remove(bundleID) != nil
        if !droppedInsideBar, !wasAcceptedDrop, Settings.pinnedBundleIDs.contains(bundleID) {
            Settings.pinnedBundleIDs.removeAll { $0 == bundleID }
            AppDelegate.shared?.rebuildBarsInPlace()
        } else if !wasAcceptedDrop {
            AppDelegate.shared?.rebuildBarsInPlace()
        }
    }

    private func setDraggedIconHidden(_ hidden: Bool) {
        guard let draggedBundleID else { return }
        for view in stackView.arrangedSubviews {
            guard let item = view as? TaskbarItemView, item.representedBundleID == draggedBundleID else { continue }
            item.isHidden = hidden
            item.alphaValue = hidden ? 0 : 1
        }
    }

    private func removeInsertionMarker() {
        guard let insertionMarker else { return }
        stackView.removeArrangedSubview(insertionMarker)
        insertionMarker.removeFromSuperview()
        self.insertionMarker = nil
    }

    private func addSeparator() {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        separator.layer?.cornerRadius = 1
        separator.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(separator)

        let margin = max(14, Settings.itemSpacing * 2)
        if Settings.edge == .left || Settings.edge == .right {
            wrapper.widthAnchor.constraint(equalToConstant: Settings.barSize - 24).isActive = true
            wrapper.heightAnchor.constraint(equalToConstant: 2 + margin * 2).isActive = true
            separator.widthAnchor.constraint(equalToConstant: Settings.barSize - 24).isActive = true
            separator.heightAnchor.constraint(equalToConstant: 2).isActive = true
            separator.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor).isActive = true
            separator.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor).isActive = true
        } else {
            wrapper.widthAnchor.constraint(equalToConstant: 2 + margin * 2).isActive = true
            wrapper.heightAnchor.constraint(equalToConstant: Settings.barSize - 24).isActive = true
            separator.widthAnchor.constraint(equalToConstant: 2).isActive = true
            separator.heightAnchor.constraint(equalToConstant: Settings.barSize - 24).isActive = true
            separator.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor).isActive = true
            separator.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor).isActive = true
        }
        stackView.addArrangedSubview(wrapper)
    }

    private func addTrashButton() {
        let image = trashIconImage()
        image.size = NSSize(width: Settings.iconSize, height: Settings.iconSize)
        let button = TaskbarItemView(title: "Trash", image: image, bundleID: nil, pid: nil, isActive: false, target: self, action: #selector(openTrashButton(_:)))
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Trash", action: #selector(menuOpenTrash(_:)), keyEquivalent: "")
        button.menu = menu
        constrain(button)
        stackView.addArrangedSubview(button)
    }

    private func trashIconImage() -> NSImage {
        let trashURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        let isEmpty = (try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil, options: []))?.isEmpty ?? true
        let assetName = isEmpty ? "trashempty.png" : "trashfull.png"
        let assetPath = "/System/Library/CoreServices/Dock.app/Contents/Resources/\(assetName)"
        if let image = NSImage(contentsOfFile: assetPath) {
            return image
        }
        return NSWorkspace.shared.icon(forFile: trashURL.path)
    }

    private func titleFor(_ app: NSRunningApplication) -> String {
        var components = [app.localizedName ?? app.bundleIdentifier ?? "App"]
        if app.isActive {
            components.append("•")
        }
        if app.isHidden {
            components.append("(hidden)")
        }
        if Settings.activityMode, let sample = activitySamples[app.processIdentifier] {
            components.append("\(sample.cpu) \(sample.memory)")
        }
        return components.joined(separator: " ")
    }

    private func badgeText(for app: NSRunningApplication) -> String? {
        if let bundleID = app.bundleIdentifier, let dockBadge = dockBadges[bundleID] {
            return dockBadge
        }
        return nil
    }

    private func shouldShow(app: NSRunningApplication) -> Bool {
        true
    }

    private func appSort(_ lhs: NSRunningApplication, _ rhs: NSRunningApplication) -> Bool {
        let left = lhs.localizedName ?? lhs.bundleIdentifier ?? ""
        let right = rhs.localizedName ?? rhs.bundleIdentifier ?? ""
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }

    private func constrain(_ button: NSButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        let tile = max(57, min(81, Settings.barSize - 14))
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: tile),
            button.widthAnchor.constraint(equalToConstant: tile)
        ])
    }

    @objc private func activateApp(_ sender: TaskbarItemView) {
        guard let bundleID = sender.representedBundleID, let app = runningApps[bundleID] else { return }
        activate(app)
    }

    @objc private func launchPinned(_ sender: TaskbarItemView) {
        guard let bundleID = sender.representedBundleID else { return }
        if let app = runningApps[bundleID] {
            activate(app)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    @objc private func openStartMenu(_ sender: NSButton) {
        applicationGridPanel.show(apps: AppDelegate.shared?.applicationURLs() ?? [], relativeTo: sender) { url in
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openTrashButton(_ sender: NSButton) {
        openTrash()
    }

    private func appMenu(_ app: NSRunningApplication) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addMenuItem(to: menu, title: "Activate", action: #selector(menuActivate(_:)), representedObject: app)
        addMenuItem(to: menu, title: app.isHidden ? "Unhide" : "Hide", action: #selector(menuHide(_:)), representedObject: app)
        menu.addItem(NSMenuItem.separator())

        let windowMenuItem = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for title in windowTitles(for: app) {
            let item = NSMenuItem(title: title, action: #selector(menuActivate(_:)), keyEquivalent: "")
            item.representedObject = app
            item.target = self
            item.isEnabled = true
            submenu.addItem(item)
        }
        if submenu.items.isEmpty {
            submenu.addItem(withTitle: "No public windows", action: nil, keyEquivalent: "")
        }
        menu.setSubmenu(submenu, for: windowMenuItem)
        menu.addItem(windowMenuItem)

        menu.addItem(NSMenuItem.separator())
        if let bundleID = app.bundleIdentifier, Settings.pinnedBundleIDs.contains(bundleID) {
            addMenuItem(to: menu, title: "Unpin from mbar", action: #selector(menuUnpin(_:)), representedObject: bundleID)
        } else if let bundleID = app.bundleIdentifier {
            addMenuItem(to: menu, title: "Pin to mbar", action: #selector(menuPin(_:)), representedObject: bundleID)
        }
        addMenuItem(to: menu, title: "Quit", action: #selector(menuQuit(_:)), representedObject: app)
        let forceQuitItem = NSMenuItem(title: "Force Quit", action: #selector(menuForceQuit(_:)), keyEquivalent: "")
        forceQuitItem.representedObject = app
        forceQuitItem.target = self
        forceQuitItem.isEnabled = true
        forceQuitItem.isAlternate = true
        forceQuitItem.keyEquivalentModifierMask = [.option]
        menu.addItem(forceQuitItem)
        return menu
    }

    private func windowTitles(for app: NSRunningApplication) -> [String] {
        let axTitles = AccessibilityWindowCatalog.windowTitles(for: app.processIdentifier)
        if !axTitles.isEmpty {
            return Array(NSOrderedSet(array: axTitles)) as? [String] ?? axTitles
        }

        let appName = app.localizedName ?? "Window"
        let cgWindows = appWindows[app.processIdentifier] ?? []
        let cgTitles = cgWindows.enumerated().map { index, window in
            let trimmed = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "Window" {
                return cgWindows.count == 1 ? appName : "\(appName) Window \(index + 1)"
            }
            return trimmed
        }
        if cgTitles.isEmpty && !AccessibilityWindowCatalog.isTrusted {
            return ["Grant mbar Accessibility permission for window titles"]
        }
        return Array(NSOrderedSet(array: cgTitles)) as? [String] ?? cgTitles
    }

    private func windowListItems(for app: NSRunningApplication) -> [WindowListItem] {
        let appName = app.localizedName ?? "Window"
        let axItems = AccessibilityWindowCatalog.windowItems(for: app.processIdentifier, appName: appName) { [weak self, weak app] in
            guard let self, let app else { return }
            self.activate(app)
        }
        if !axItems.isEmpty {
            return axItems
        }

        return windowTitles(for: app).map { title in
            WindowListItem(title: title) { [weak self, weak app] in
                guard let self, let app else { return }
                self.activate(app)
            }
        }
    }

    private func addMenuItem(to menu: NSMenu, title: String, action: Selector, representedObject: Any) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.representedObject = representedObject
        item.target = self
        item.isEnabled = true
        menu.addItem(item)
    }

    private func pinnedMenu(bundleID: String) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addMenuItem(to: menu, title: "Open", action: #selector(menuLaunchPinned(_:)), representedObject: bundleID)
        addMenuItem(to: menu, title: "Unpin from mbar", action: #selector(menuUnpin(_:)), representedObject: bundleID)
        return menu
    }

    private func startMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Applications", action: nil, keyEquivalent: "").submenu = applicationsMenu()
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Show Desktop", action: #selector(menuShowDesktop(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open Trash", action: #selector(menuOpenTrash(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: Settings.mirror ? "Disable Mirror Mode" : "Enable Mirror Mode", action: #selector(menuToggleMirror(_:)), keyEquivalent: "")
        menu.addItem(withTitle: Settings.activityMode ? "Disable Activity Mode" : "Enable Activity Mode", action: #selector(menuToggleActivity(_:)), keyEquivalent: "")

        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        for edge in Edge.allCases {
            let item = NSMenuItem(title: edge.rawValue.capitalized, action: #selector(menuSetEdge(_:)), keyEquivalent: "")
            item.representedObject = edge.rawValue
            item.state = Settings.edge == edge ? .on : .off
            positionMenu.addItem(item)
        }
        menu.setSubmenu(positionMenu, for: positionItem)
        menu.addItem(positionItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Lock Screen", action: #selector(menuLock(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Sleep", action: #selector(menuSleep(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Restart…", action: #selector(menuRestart(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Shut Down…", action: #selector(menuShutdown(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit mbar", action: #selector(menuQuitApp(_:)), keyEquivalent: "q")
        return menu
    }

    private func applicationsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for url in AppDelegate.shared?.applicationURLs() ?? [] {
            let title = url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 22, height: 22)
            let item = NSMenuItem(title: title, action: #selector(menuOpenURL(_:)), keyEquivalent: "")
            item.image = icon
            item.representedObject = url
            item.target = self
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            menu.addItem(withTitle: "No applications found", action: nil, keyEquivalent: "").isEnabled = false
        }
        return menu
    }

    private func barContextMenu() -> NSMenu {
        isBarMenuOpen = true
        hideWorkItem?.cancel()
        reveal()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "mbar Settings…", action: #selector(menuOpenSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let hidingItem = NSMenuItem(title: "Auto-Hide Enabled", action: nil, keyEquivalent: "")
        hidingItem.state = .on
        hidingItem.isEnabled = false
        menu.addItem(hidingItem)

        let activityItem = NSMenuItem(title: Settings.activityMode ? "Disable Activity Mode" : "Enable Activity Mode", action: #selector(menuToggleActivity(_:)), keyEquivalent: "")
        activityItem.target = self
        activityItem.isEnabled = true
        menu.addItem(activityItem)

        let positionItem = NSMenuItem(title: "Position on Screen", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu()
        positionMenu.autoenablesItems = false
        for edge in Edge.allCases {
            let item = NSMenuItem(title: edge.rawValue.capitalized, action: #selector(menuSetEdge(_:)), keyEquivalent: "")
            item.representedObject = edge.rawValue
            item.target = self
            item.isEnabled = true
            item.state = Settings.edge == edge ? .on : .off
            positionMenu.addItem(item)
        }
        menu.setSubmenu(positionMenu, for: positionItem)
        menu.addItem(positionItem)

        menu.addItem(NSMenuItem.separator())
        let dockSettingsItem = NSMenuItem(title: "Open Desktop & Dock Settings…", action: #selector(menuOpenDockSettings(_:)), keyEquivalent: "")
        dockSettingsItem.target = self
        dockSettingsItem.isEnabled = true
        menu.addItem(dockSettingsItem)

        let accessibilityItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(menuOpenAccessibilitySettings(_:)), keyEquivalent: "")
        accessibilityItem.target = self
        accessibilityItem.isEnabled = true
        menu.addItem(accessibilityItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit mbar", action: #selector(menuQuitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)
        return menu
    }

    func menuDidClose(_ menu: NSMenu) {
        guard isBarMenuOpen else { return }
        isBarMenuOpen = false
        scheduleHide()
    }

    @objc private func menuActivate(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        activate(app)
    }

    private func activate(_ app: NSRunningApplication) {
        AccessibilityWindowCatalog.unminimizeWindows(for: app.processIdentifier)
        app.unhide()
        app.activate(options: [.activateAllWindows])
    }

    @objc private func menuHide(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        if app.isHidden {
            _ = app.unhide()
        } else {
            _ = app.hide()
        }
    }

    @objc private func menuQuit(_ sender: NSMenuItem) {
        (sender.representedObject as? NSRunningApplication)?.terminate()
    }

    @objc private func menuForceQuit(_ sender: NSMenuItem) {
        (sender.representedObject as? NSRunningApplication)?.forceTerminate()
    }

    @objc private func menuPin(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        Settings.pinnedBundleIDs.append(bundleID)
        AppDelegate.shared?.rebuildBars()
    }

    @objc private func menuUnpin(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        Settings.pinnedBundleIDs.removeAll { $0 == bundleID }
        AppDelegate.shared?.rebuildBars()
    }

    @objc private func menuLaunchPinned(_ sender: NSMenuItem) {
        guard
            let bundleID = sender.representedObject as? String,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    @objc private func menuOpenURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func menuOpenSettings(_ sender: NSMenuItem) {
        AppDelegate.shared?.showSettings()
    }

    @objc private func menuOpenDockSettings(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }

    @objc private func menuOpenAccessibilitySettings(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func menuShowDesktop(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop"))
    }

    @objc private func menuOpenTrash(_ sender: NSMenuItem) {
        openTrash()
    }

    private func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash"))
    }

    @objc private func menuToggleMirror(_ sender: NSMenuItem) {
        Settings.mirror.toggle()
        AppDelegate.shared?.rebuildBars()
    }

    @objc private func menuToggleActivity(_ sender: NSMenuItem) {
        Settings.activityMode.toggle()
        AppDelegate.shared?.rebuildBars()
    }

    @objc private func menuSetEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let edge = Edge(rawValue: raw) else { return }
        Settings.edge = edge
        AppDelegate.shared?.rebuildBars()
    }

    @objc private func menuLock(_ sender: NSMenuItem) {
        runSystemCommand("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession", ["-suspend"])
    }

    @objc private func menuSleep(_ sender: NSMenuItem) {
        runSystemCommand("/usr/bin/pmset", ["sleepnow"])
    }

    @objc private func menuRestart(_ sender: NSMenuItem) {
        runAppleScript("tell application \"System Events\" to restart")
    }

    @objc private func menuShutdown(_ sender: NSMenuItem) {
        runAppleScript("tell application \"System Events\" to shut down")
    }

    @objc private func menuQuitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func runSystemCommand(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try? process.run()
    }

    private func runAppleScript(_ script: String) {
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var controllers: [TaskbarController] = []
    private let settingsWindowController = SettingsWindowController()
    private let applicationCatalog = ApplicationCatalog()
    private var timer: Timer?
    private var applicationCatalogTimer: Timer?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

    var isSettingsVisible: Bool {
        settingsWindowController.window?.isVisible == true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        AccessibilityWindowCatalog.requestTrustIfNeeded()
        applicationCatalog.refreshIfNeeded(force: true)
        settingsWindowController.onClose = { [weak self] in
            guard Settings.autoHide else { return }
            self?.controllers.forEach { $0.scheduleHide() }
        }
        rebuildBars()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: NSWorkspace.didHideApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(workspaceChanged(_:)), name: NSWorkspace.didUnhideApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.controllers.forEach { $0.rebuild() }
            }
        }
        applicationCatalogTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applicationCatalog.refreshIfNeeded(force: true)
            }
        }

        installInteractionMonitors()
    }

    func applicationURLs() -> [URL] {
        applicationCatalog.refreshIfNeeded()
        return applicationCatalog.urls
    }

    func rebuildBars(preserveVisibility: Bool = false) {
        controllers.forEach { $0.panel.orderOut(nil) }
        controllers = NSScreen.screens.map(TaskbarController.init(screen:))
        controllers.forEach {
            $0.rebuild()
            if preserveVisibility {
                $0.triggerPanel.orderFrontRegardless()
                $0.reveal()
            } else {
                $0.show()
            }
        }
    }

    func rebuildBarsInPlace() {
        controllers.forEach { $0.rebuild() }
    }

    func refreshBarLayout() {
        controllers.forEach { $0.refreshLayout() }
    }

    func refreshBarTheme() {
        controllers.forEach { $0.refreshTheme() }
    }

    func showSettings() {
        settingsWindowController.showAndRefresh()
        controllers.forEach { $0.reveal() }
    }

    func applyAutoHidePreference() {
        if Settings.autoHide {
            controllers.forEach { $0.scheduleHide() }
        } else {
            controllers.forEach { $0.reveal() }
        }
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        controllers.forEach { $0.rebuild() }
    }

    @objc private func screenChanged(_ notification: Notification) {
        rebuildBars()
    }

    private func installInteractionMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handleExternalInteraction(event)
            }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleExternalInteraction(event)
            return event
        }
    }

    private func handleExternalInteraction(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            controllers.forEach { $0.hideForExternalInteraction() }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            controllers.forEach { $0.hideForExternalInteraction(at: NSEvent.mouseLocation) }
        default:
            break
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
