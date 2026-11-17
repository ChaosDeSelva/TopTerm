import AppKit
import TopTermCore

final class TerminalPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        title = "TopTerm"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        hasShadow = true
        backgroundColor = Palette.background
        appearance = NSAppearance(named: .darkAqua)
        animationBehavior = .none
        setAccessibilityLabel("TopTerm terminal drawer")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    func followActiveSpace() {
        if !isOnActiveSpace {
            // Reapply membership if the window server left this visible drawer on the old Desktop.
            collectionBehavior.remove(.canJoinAllSpaces)
            collectionBehavior.insert(.canJoinAllSpaces)
        }
        orderFrontRegardless()
    }
}

final class PanelContent: NSView {
    let terminalHost = NSView()
    private let brand = NSTextField(labelWithString: "›_  TOPTERM")
    private let tabs = NSScrollView()
    private let tabDocument = NSView()
    private let add = NSButton()
    private let heightButton = NSButton()
    private let expand = NSButton()
    private let hide = NSButton()
    private let footer = NSTextField(labelWithString: "")
    private let shortcutHint = NSButton(title: "⌃`  show / hide", target: nil, action: nil)
    private let resizeHandle = ResizeHandle()
    private var tabViews: [TabView] = []
    var onNew: (() -> Void)?
    var onHide: (() -> Void)?
    var onExpand: (() -> Void)?
    var onHeight: ((NSView) -> Void)?
    var onResize: ((CGFloat) -> Void)?
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?
    var onShortcut: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Palette.background.cgColor
        brand.font = .systemFont(ofSize: 11, weight: .bold)
        brand.textColor = Palette.accent
        brand.setAccessibilityLabel("TopTerm")
        tabs.documentView = tabDocument
        tabs.drawsBackground = false
        tabs.hasHorizontalScroller = false
        tabs.hasVerticalScroller = false
        configure(add, symbol: "plus", label: "New tab (⌘T)", action: #selector(newTab))
        configure(expand, symbol: "arrow.up.left.and.arrow.down.right", label: "Toggle full height (⌘Return)", action: #selector(expandPanel))
        configure(hide, symbol: "chevron.up", label: "Hide terminal (⌃`)", action: #selector(hidePanel))
        heightButton.title = "\(Int(PanelGeometry.defaultFraction * 100))%"
        heightButton.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        heightButton.bezelStyle = .recessed
        heightButton.isBordered = false
        heightButton.target = self
        heightButton.action = #selector(chooseHeight)
        heightButton.toolTip = "Set panel height, or drag the bottom edge"
        heightButton.setAccessibilityLabel("Panel height")
        footer.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingMiddle
        shortcutHint.font = .systemFont(ofSize: 10)
        shortcutHint.contentTintColor = .secondaryLabelColor
        shortcutHint.isBordered = false
        shortcutHint.alignment = .right
        shortcutHint.target = self
        shortcutHint.action = #selector(recordShortcut)
        shortcutHint.toolTip = "Change the show / hide shortcut"
        shortcutHint.setAccessibilityLabel("Change show and hide shortcut")
        resizeHandle.onDrag = { [weak self] y in self?.onResize?(y) }
        for view in [brand, tabs, add, heightButton, expand, hide, terminalHost, footer, shortcutHint, resizeHandle] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.bezelStyle = .recessed
        button.isBordered = false
        button.contentTintColor = Palette.foreground
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let headerY = bounds.height - 43
        brand.frame = NSRect(x: 16, y: headerY + 10, width: 96, height: 16)
        hide.frame = NSRect(x: w - 44, y: headerY, width: 32, height: 34)
        expand.frame = NSRect(x: w - 80, y: headerY, width: 32, height: 34)
        heightButton.frame = NSRect(x: w - 142, y: headerY, width: 54, height: 34)
        let tabWidth = min(CGFloat(max(1, tabViews.count)) * 200, max(0, w - 310))
        tabs.frame = NSRect(x: 118, y: headerY, width: tabWidth, height: 34)
        add.frame = NSRect(x: 124 + tabWidth, y: headerY, width: 32, height: 34)
        layoutTabs()
        terminalHost.frame = NSRect(x: 12, y: 29, width: max(0, w - 24), height: max(0, bounds.height - 77))
        footer.frame = NSRect(x: 16, y: 10, width: max(0, w - 190), height: 14)
        shortcutHint.frame = NSRect(x: w - 170, y: 10, width: 154, height: 14)
        resizeHandle.frame = NSRect(x: 0, y: 0, width: w, height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.chrome.setFill()
        NSRect(x: 0, y: bounds.height - 48, width: bounds.width, height: 48).fill()
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSRect(x: 0, y: bounds.height - 48, width: bounds.width, height: 1).fill()
    }

    func update(sessions: [TerminalSession], active: Int, fraction: Double, expanded: Bool, shortcutWorks: Bool, shortcutLabel: String) {
        while tabViews.count > sessions.count { tabViews.removeLast().removeFromSuperview() }
        while tabViews.count < sessions.count {
            let view = TabView()
            tabDocument.addSubview(view)
            tabViews.append(view)
        }
        for (index, session) in sessions.enumerated() {
            tabViews[index].update(title: session.displayTitle, selected: index == active, ended: session.ended)
            tabViews[index].onSelect = { [weak self] in self?.onSelect?(index) }
            tabViews[index].onClose = { [weak self] in self?.onClose?(index) }
            tabViews[index].onRename = { [weak self] in self?.onRename?(index) }
        }
        let savedHeight = "\(Int((fraction * 100).rounded()))%"
        heightButton.title = expanded ? "100%" : savedHeight
        heightButton.toolTip = expanded ? "Full height · saved height \(savedHeight)" : "Set panel height, or drag the bottom edge"
        expand.image = NSImage(systemSymbolName: expanded ? "arrow.down.right.and.arrow.up.left" :
                                "arrow.up.left.and.arrow.down.right", accessibilityDescription: expanded ? "Restore saved height" : "Full height")
        expand.toolTip = expanded ? "Restore saved height (⌘Return)" : "Full height (⌘Return)"
        if sessions.indices.contains(active) {
            let session = sessions[active]
            let path = (session.directory as NSString).abbreviatingWithTildeInPath
            let git = session.gitStatus.map { "   ·   \($0.branch)\($0.dirty ? " *" : "")" } ?? ""
            footer.toolTip = "Current shell directory. A * after the Git branch means uncommitted changes, including untracked files."
            footer.stringValue = "\(session.ended ? "○ Ended" : "● " + URL(fileURLWithPath: session.shell).lastPathComponent)   ·   \(path)" + git
        }
        shortcutHint.title = shortcutWorks ? "\(shortcutLabel)  show / hide" : "Set a shortcut…"
        hide.toolTip = "Hide terminal (\(shortcutLabel))"
        hide.setAccessibilityLabel("Hide terminal (\(shortcutLabel))")
        needsLayout = true
    }

    func revealTab(_ index: Int) {
        layoutSubtreeIfNeeded()
        guard tabViews.indices.contains(index) else { return }
        tabDocument.scrollToVisible(tabViews[index].frame)
    }

    private func layoutTabs() {
        let width = min(200, max(130, tabs.bounds.width / CGFloat(max(1, tabViews.count))))
        tabDocument.frame = NSRect(x: 0, y: 0, width: max(tabs.bounds.width, CGFloat(tabViews.count) * width), height: 34)
        for (index, tab) in tabViews.enumerated() {
            tab.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width - 4, height: 34)
        }
    }

    @objc private func newTab() { onNew?() }
    @objc private func hidePanel() { onHide?() }
    @objc private func expandPanel() { onExpand?() }
    @objc private func chooseHeight() { onHeight?(heightButton) }
    @objc private func recordShortcut() { onShortcut?() }
}

private final class TabView: NSView {
    private let select = NSButton()
    private let close = NSButton()
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onRename: (() -> Void)?
    private var selected = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        select.isBordered = false
        select.alignment = .left
        select.font = .systemFont(ofSize: 12, weight: .medium)
        select.lineBreakMode = .byTruncatingTail
        select.target = self
        select.action = #selector(selectedTab)
        let contextMenu = NSMenu()
        let rename = NSMenuItem(title: "Rename Tab…", action: #selector(renameTab), keyEquivalent: "")
        rename.target = self
        contextMenu.addItem(rename)
        menu = contextMenu
        select.menu = contextMenu
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        close.imageScaling = .scaleProportionallyDown
        close.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        close.isBordered = false
        close.target = self
        close.action = #selector(closedTab)
        close.toolTip = "Close tab (⌘W)"
        close.setAccessibilityLabel("Close tab")
        addSubview(select)
        addSubview(close)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(title: String, selected: Bool, ended: Bool) {
        self.selected = selected
        select.title = "\(ended ? "○" : "›")  \(title.isEmpty ? "Shell" : title)"
        select.toolTip = "\(title) · Double-click to rename"
        select.contentTintColor = selected ? Palette.foreground : .secondaryLabelColor
        close.contentTintColor = .secondaryLabelColor
        layer?.backgroundColor = (selected ? NSColor.white.withAlphaComponent(0.08) : .clear).cgColor
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        select.frame = NSRect(x: 9, y: 2, width: max(0, bounds.width - 36), height: 30)
        close.frame = NSRect(x: bounds.width - 30, y: 5, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            Palette.accent.setFill()
            NSRect(x: 10, y: 0, width: max(0, bounds.width - 20), height: 2).fill()
        }
    }

    @objc private func selectedTab() {
        onSelect?()
        if NSApp.currentEvent?.clickCount == 2 { onRename?() }
    }
    @objc private func renameTab() { onRename?() }
    @objc private func closedTab() { onClose?() }
}

private final class ResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) { onDrag?(NSEvent.mouseLocation.y) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 22, y: 2, width: 44, height: 2), xRadius: 1, yRadius: 1).fill()
    }
}
