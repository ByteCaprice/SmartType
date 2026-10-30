import AppKit

@MainActor final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    static let shared = SettingsWindowController()
    static let frameAutosaveName = "SwiftTypeSettingsWindow"

    enum Tab: String, CaseIterable {
        case customization
        case about

        var title: String {
            switch self {
            case .customization: "Appearance"
            case .about: "About"
            }
        }

        var icon: String {
            switch self {
            case .customization: "paintbrush"
            case .about: "info.circle"
            }
        }

        var toolbarIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier(rawValue)
        }
    }

    var colorWells: [ThemeColorKey: NSColorWell] = [:]
    var highlightOpacitySlider: NSSlider!
    var highlightOpacityLabel: NSTextField!
    var candidateCountPopUp: NSPopUpButton!
    var gridRowsPopUp: NSPopUpButton!
    var candidateLayoutPopUp: NSPopUpButton!
    var candidatePreview: CandidateView?
    var candidatePreviewBackground: NSVisualEffectView?

    var customizationPane: NSView?
    var aboutPane: NSView?

    enum Layout {
        static let windowWidth: CGFloat = 550
        static let initialPaneHeight: CGFloat = 400
        static let edgeInset: CGFloat = 24
        static let buttonSpacing: CGFloat = 8
        static let colorWellSize: CGFloat = 28
        static let popUpWidth: CGFloat = 180
        static let sliderWidth: CGFloat = 144
        static let sliderLabelWidth: CGFloat = 36
        static let rowLabelWidth: CGFloat = 160
        static let headerFontSize: CGFloat = 13
        static let rowSpacing: CGFloat = 10
        static let sectionSpacing: CGFloat = 18
    }

    private convenience init() {
        let window = Self.makeWindow()
        self.init(window: window)
        windowFrameAutosaveName = Self.frameAutosaveName
        window.delegate = self
        setupToolbar()
        selectTab(.customization, animate: false)
    }

    func showWindow(tab: Tab = .customization) {
        if customizationPane != nil { syncCustomizationControls() }
        selectTab(tab, animate: window?.isVisible == true)
        NSApp.setActivationPolicy(.regular)
        window?.collectionBehavior = .canJoinAllSpaces
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.collectionBehavior = []
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.initialPaneHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
        )
        window.title = "SmartType Settings"
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = Tab.customization.toolbarIdentifier
        window?.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(_: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem? {
        guard let tab = Tab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let tab = Tab(rawValue: sender.itemIdentifier.rawValue) else { return }
        selectTab(tab)
    }

    func selectTab(_ tab: Tab, animate: Bool = true) {
        window?.toolbar?.selectedItemIdentifier = tab.toolbarIdentifier

        let paneView: NSView
        switch tab {
        case .customization:
            if customizationPane == nil { customizationPane = makeCustomizationTab() }
            paneView = customizationPane!
        case .about:
            if aboutPane == nil { aboutPane = makeAboutTab() }
            paneView = aboutPane!
        }

        paneView.layoutSubtreeIfNeeded()
        window?.contentView = paneView

        guard let window else { return }
        let paneHeight = paneView.fittingSize.height
        let newFrameSize = window.frameRect(
            forContentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: paneHeight),
        ).size
        var frame = window.frame
        frame.origin.y += frame.size.height - newFrameSize.height
        frame.size = newFrameSize
        window.setFrame(frame, display: true, animate: animate)
    }

    func windowWillClose(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func makeContentStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    func makeRowLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: Layout.headerFontSize)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: Layout.rowLabelWidth).isActive = true
        return label
    }

    func makeColorWell(color: NSColor, action: Selector) -> NSColorWell {
        let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: Layout.colorWellSize, height: Layout.colorWellSize))
        well.color = color
        well.colorWellStyle = .minimal
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: Layout.colorWellSize).isActive = true
        well.heightAnchor.constraint(equalToConstant: Layout.colorWellSize).isActive = true
        well.target = self
        well.action = action
        return well
    }

    func makePopUp(items: [String], selectedIndex: Int, action: Selector) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        items.forEach { popUp.addItem(withTitle: $0) }
        popUp.selectItem(at: selectedIndex)
        popUp.target = self
        popUp.action = action
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.widthAnchor.constraint(equalToConstant: Layout.popUpWidth).isActive = true
        return popUp
    }

    func makeSettingsRow(label title: String, control: NSView) -> NSView {
        control.setAccessibilityLabel(title)
        let row = NSStackView(views: [makeRowLabel(title), control])
        row.alignment = .centerY
        row.spacing = Layout.buttonSpacing
        return row
    }

    func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.textColor = .labelColor
        return label
    }
}
