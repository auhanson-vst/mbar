import AppKit
import ApplicationServices
import CoreGraphics

enum Edge: String, CaseIterable {
    case bottom
    case top
    case left
    case right
}

struct Settings {
    private enum Key {
        static let edge = "edge"
        static let mirror = "mirror"
        static let activityMode = "activityMode"
        static let rows = "rows"
        static let barSize = "barSize"
        static let iconSize = "iconSize"
        static let pinnedBundleIDs = "pinnedBundleIDs"
    }

    static var edge: Edge {
        get { Edge(rawValue: UserDefaults.standard.string(forKey: Key.edge) ?? "") ?? .bottom }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.edge) }
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
            return value == 0 ? 52 : CGFloat(max(36, min(140, value)))
        }
        set { UserDefaults.standard.set(Double(max(36, min(140, newValue))), forKey: Key.barSize) }
    }

    static var iconSize: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: Key.iconSize)
            return value == 0 ? 28 : CGFloat(max(16, min(64, value)))
        }
        set { UserDefaults.standard.set(Double(max(16, min(64, newValue))), forKey: Key.iconSize) }
    }

    static var pinnedBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: Key.pinnedBundleIDs) ?? [] }
        set { UserDefaults.standard.set(Array(NSOrderedSet(array: newValue)) as? [String] ?? newValue, forKey: Key.pinnedBundleIDs) }
    }
}

struct WindowInfo {
    let ownerPID: pid_t
    let title: String
    let bounds: CGRect
}

struct ProcessSample {
    let cpu: String
    let memory: String
}

@MainActor
final class HoverView: NSView {
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
final class TaskbarItemView: NSButton {
    let representedBundleID: String?
    let representedPID: pid_t?
    private let normalBackground: CGColor
    private let hoverBackground: CGColor
    private let pressedBackground: CGColor

    init(title: String, image: NSImage?, bundleID: String?, pid: pid_t?, isActive: Bool = false, isHidden: Bool = false, attention: Bool = false, target: AnyObject?, action: Selector?) {
        self.representedBundleID = bundleID
        self.representedPID = pid
        let baseColor: NSColor = {
            if attention { return .systemRed.withAlphaComponent(0.28) }
            if isActive { return .controlAccentColor.withAlphaComponent(0.22) }
            if isHidden { return .white.withAlphaComponent(0.05) }
            return .white.withAlphaComponent(0.11)
        }()
        self.normalBackground = baseColor.cgColor
        self.hoverBackground = baseColor.blended(withFraction: 0.35, of: .white)?.cgColor ?? NSColor.white.withAlphaComponent(0.2).cgColor
        self.pressedBackground = NSColor.controlAccentColor.withAlphaComponent(0.34).cgColor
        super.init(frame: .zero)
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
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = isActive ? 1 : 0
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        layer?.backgroundColor = normalBackground
        contentTintColor = isHidden ? .tertiaryLabelColor : nil
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
        animateTile(background: hoverBackground, scale: 1.08)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        animateTile(background: normalBackground, scale: 1.0)
    }

    override var isHighlighted: Bool {
        didSet {
            layer?.backgroundColor = isHighlighted ? pressedBackground : normalBackground
        }
    }

    private func animateTile(background: CGColor, scale: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().layer?.backgroundColor = background
            animator().layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        }
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
final class TaskbarController: NSObject {
    let screen: NSScreen
    let panel: TaskbarPanel
    let triggerPanel: TaskbarPanel
    let stackView = NSStackView()
    private let hoverView = HoverView()
    private let triggerView = HoverView()
    private var runningApps: [String: NSRunningApplication] = [:]
    private var appWindows: [pid_t: [WindowInfo]] = [:]
    private var activitySamples: [pid_t: ProcessSample] = [:]
    private var hideWorkItem: DispatchWorkItem?
    private var isRevealed = false

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
        hide(animated: false)
    }

    func rebuild() {
        panel.setFrame(Self.frame(for: screen), display: true, animate: false)
        triggerPanel.setFrame(Self.triggerFrame(for: screen), display: true, animate: false)
        stackView.orientation = Settings.edge == .left || Settings.edge == .right ? .vertical : .horizontal
        let windows = WindowCatalog.visibleWindows()
        appWindows = Dictionary(grouping: windows, by: \.ownerPID)
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular && app.bundleIdentifier != Bundle.main.bundleIdentifier
            }

        runningApps = Dictionary(uniqueKeysWithValues: apps.compactMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return (bundleID, app)
        })

        if Settings.activityMode {
            activitySamples = ActivitySampler.samples(for: apps.map(\.processIdentifier))
        } else {
            activitySamples = [:]
        }

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        addStartButton()
        addFlexibleSpacer()

        let pinnedIDs = Settings.pinnedBundleIDs
        for bundleID in pinnedIDs {
            addPinnedItem(bundleID: bundleID)
        }

        for app in apps.sorted(by: appSort) {
            guard shouldShow(app: app), app.bundleIdentifier.map({ !pinnedIDs.contains($0) }) ?? true else { continue }
            addAppItem(app)
        }

        addSeparator()
        addTrashButton()
    }

    private func buildChrome() {
        let effect = NSVisualEffectView()
        effect.blendingMode = .behindWindow
        effect.material = .underWindowBackground
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        stackView.orientation = Settings.edge == .left || Settings.edge == .right ? .vertical : .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .gravityAreas
        stackView.spacing = 7
        stackView.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        hoverView.onEnter = { [weak self] in self?.reveal() }
        hoverView.onExit = { [weak self] in self?.scheduleHide() }
        hoverView.translatesAutoresizingMaskIntoConstraints = false
        hoverView.addSubview(effect)
        effect.addSubview(stackView)
        panel.contentView = hoverView

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor, constant: 8),
            effect.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor, constant: -8),
            effect.topAnchor.constraint(equalTo: hoverView.topAnchor, constant: 5),
            effect.bottomAnchor.constraint(equalTo: hoverView.bottomAnchor, constant: -5),
            stackView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: effect.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
    }

    private func buildTrigger() {
        triggerView.onEnter = { [weak self] in self?.reveal() }
        triggerView.onExit = { [weak self] in self?.scheduleHide() }
        triggerView.wantsLayer = true
        triggerView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        triggerPanel.contentView = triggerView
        triggerPanel.hasShadow = false
        triggerPanel.alphaValue = 0.45
    }

    private func reveal() {
        hideWorkItem?.cancel()
        guard !isRevealed else { return }
        isRevealed = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let mouse = NSEvent.mouseLocation
                if self.panel.frame.contains(mouse) || self.triggerPanel.frame.contains(mouse) {
                    self.scheduleHide()
                } else {
                    self.hide(animated: true)
                }
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    private func hide(animated: Bool) {
        hideWorkItem?.cancel()
        isRevealed = false
        guard panel.isVisible else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.13
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    self.panel.orderOut(nil)
                    self.panel.alphaValue = 1
                }
            }
        } else {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func addStartButton() {
        let button = TaskbarItemView(title: "Apps", image: NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Apps"), bundleID: nil, pid: nil, isActive: false, target: self, action: #selector(openStartMenu(_:)))
        button.menu = startMenu()
        constrain(button)
        stackView.addArrangedSubview(button)
    }

    private func addFlexibleSpacer() {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        if Settings.edge == .left || Settings.edge == .right {
            spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true
        } else {
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true
        }
        stackView.addArrangedSubview(spacer)
    }

    private func addPinnedItem(bundleID: String) {
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
        constrain(button)
        stackView.addArrangedSubview(button)
    }

    private func addAppItem(_ app: NSRunningApplication) {
        let title = titleFor(app)
        let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: title)
        icon?.size = NSSize(width: Settings.iconSize, height: Settings.iconSize)
        let attention = app.isHidden == false && app.isActive == false && appWindows[app.processIdentifier]?.isEmpty == false
        let button = TaskbarItemView(title: title, image: icon, bundleID: app.bundleIdentifier, pid: app.processIdentifier, isActive: app.isActive, isHidden: app.isHidden, attention: attention, target: self, action: #selector(activateApp(_:)))
        button.menu = appMenu(app)
        constrain(button)
        stackView.addArrangedSubview(button)
    }

    private func addSeparator() {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        if Settings.edge == .left || Settings.edge == .right {
            separator.widthAnchor.constraint(equalToConstant: Settings.barSize - 20).isActive = true
        } else {
            separator.heightAnchor.constraint(equalToConstant: Settings.barSize - 20).isActive = true
        }
        stackView.addArrangedSubview(separator)
    }

    private func addTrashButton() {
        let image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Trash")
        image?.size = NSSize(width: Settings.iconSize, height: Settings.iconSize)
        let button = TaskbarItemView(title: "Trash", image: image, bundleID: nil, pid: nil, isActive: false, target: self, action: #selector(openTrashButton(_:)))
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Trash", action: #selector(menuOpenTrash(_:)), keyEquivalent: "")
        button.menu = menu
        constrain(button)
        stackView.addArrangedSubview(button)
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

    private func shouldShow(app: NSRunningApplication) -> Bool {
        guard !Settings.mirror else { return true }
        guard let windows = appWindows[app.processIdentifier], !windows.isEmpty else {
            return app.bundleIdentifier.map { Settings.pinnedBundleIDs.contains($0) } ?? false
        }
        return windows.contains { screen.frame.intersects($0.bounds) }
    }

    private func appSort(_ lhs: NSRunningApplication, _ rhs: NSRunningApplication) -> Bool {
        let left = lhs.localizedName ?? lhs.bundleIdentifier ?? ""
        let right = rhs.localizedName ?? rhs.bundleIdentifier ?? ""
        return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }

    private func constrain(_ button: NSButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        let tile = max(38, min(54, Settings.barSize - 14))
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: tile),
            button.widthAnchor.constraint(equalToConstant: tile)
        ])
    }

    @objc private func activateApp(_ sender: TaskbarItemView) {
        guard let bundleID = sender.representedBundleID, let app = runningApps[bundleID] else { return }
        app.activate(options: [.activateAllWindows])
    }

    @objc private func launchPinned(_ sender: TaskbarItemView) {
        guard let bundleID = sender.representedBundleID else { return }
        if let app = runningApps[bundleID] {
            app.activate(options: [.activateAllWindows])
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    @objc private func openStartMenu(_ sender: NSButton) {
        sender.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func openTrashButton(_ sender: NSButton) {
        openTrash()
    }

    private func appMenu(_ app: NSRunningApplication) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Activate", action: #selector(menuActivate(_:)), keyEquivalent: "").representedObject = app
        menu.addItem(withTitle: app.isHidden ? "Unhide" : "Hide", action: #selector(menuHide(_:)), keyEquivalent: "").representedObject = app
        menu.addItem(NSMenuItem.separator())

        let windowMenuItem = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for window in appWindows[app.processIdentifier] ?? [] {
            let item = NSMenuItem(title: window.title, action: #selector(menuActivate(_:)), keyEquivalent: "")
            item.representedObject = app
            submenu.addItem(item)
        }
        if submenu.items.isEmpty {
            submenu.addItem(withTitle: "No public windows", action: nil, keyEquivalent: "")
        }
        menu.setSubmenu(submenu, for: windowMenuItem)
        menu.addItem(windowMenuItem)

        menu.addItem(NSMenuItem.separator())
        if let bundleID = app.bundleIdentifier, Settings.pinnedBundleIDs.contains(bundleID) {
            menu.addItem(withTitle: "Unpin from mbar", action: #selector(menuUnpin(_:)), keyEquivalent: "").representedObject = bundleID
        } else if let bundleID = app.bundleIdentifier {
            menu.addItem(withTitle: "Pin to mbar", action: #selector(menuPin(_:)), keyEquivalent: "").representedObject = bundleID
        }
        menu.addItem(withTitle: "Quit", action: #selector(menuQuit(_:)), keyEquivalent: "").representedObject = app
        return menu
    }

    private func pinnedMenu(bundleID: String) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Launch", action: #selector(menuLaunchPinned(_:)), keyEquivalent: "").representedObject = bundleID
        menu.addItem(withTitle: "Unpin from mbar", action: #selector(menuUnpin(_:)), keyEquivalent: "").representedObject = bundleID
        return menu
    }

    private func startMenu() -> NSMenu {
        let menu = NSMenu()
        let appsItem = NSMenuItem(title: "Applications", action: nil, keyEquivalent: "")
        let appsMenu = NSMenu()
        let applicationURLs = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        for url in applicationURLs.filter({ $0.pathExtension == "app" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(80) {
            let item = NSMenuItem(title: url.deletingPathExtension().lastPathComponent, action: #selector(menuOpenURL(_:)), keyEquivalent: "")
            item.representedObject = url
            appsMenu.addItem(item)
        }
        menu.setSubmenu(appsMenu, for: appsItem)
        menu.addItem(appsItem)
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

    @objc private func menuActivate(_ sender: NSMenuItem) {
        (sender.representedObject as? NSRunningApplication)?.activate(options: [.activateAllWindows])
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
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
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
    }

    func rebuildBars() {
        controllers.forEach { $0.panel.orderOut(nil) }
        controllers = NSScreen.screens.map(TaskbarController.init(screen:))
        controllers.forEach {
            $0.rebuild()
            $0.show()
        }
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        controllers.forEach { $0.rebuild() }
    }

    @objc private func screenChanged(_ notification: Notification) {
        rebuildBars()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
