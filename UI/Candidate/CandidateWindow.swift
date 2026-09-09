import AppKit
import InputMethodKit

@MainActor private final class CandidateBackgroundView: NSVisualEffectView {
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

@MainActor final class CandidateWindow {
    static let shared = CandidateWindow()

    private enum Layout {
        static let fallbackLineHeight: CGFloat = 20
        static let cursorGap: CGFloat = 4
        static let minWidth: CGFloat = 100
        static let minHeight: CGFloat = 30
    }

    private let panel: NSPanel
    private let candidateView: CandidateView
    private let backgroundView: CandidateBackgroundView

    // MARK: - Grid state

    private var gridState: GridCandidateState?
    private var candidateLayout = CandidateLayout.grid
    private var hasActiveSelection = false
    /// Cached cursor rect — reused when reflowing the panel on expand / collapse.
    private var lastCursorRect: NSRect = .zero
    private var lastValidCursorRect: NSRect?
    private var cursorClientIdentifier: ObjectIdentifier?

    // MARK: - Public accessors

    var isVisible: Bool {
        panel.isVisible
    }

    var isLiteralSelected: Bool {
        gridState?.isLiteralSelected ?? false
    }

    var accessibilityCandidateLabels: [String] {
        candidateView.accessibilityCandidateLabels
    }

    var accessibilitySelectedCandidateLabel: String? {
        candidateView.accessibilitySelectedCandidateLabel
    }

    // MARK: - Init

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true,
        )
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        backgroundView = CandidateBackgroundView(frame: panel.contentView!.bounds)
        backgroundView.material = .popover
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.isEmphasized = false
        backgroundView.wantsLayer = true
        backgroundView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(backgroundView)

        candidateView = CandidateView(frame: backgroundView.bounds)
        candidateView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(candidateView)

        NSLayoutConstraint.activate([
            candidateView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            candidateView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            candidateView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            candidateView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
        ])

        backgroundView.appearanceDidChange = { [weak self] in
            self?.applyTheme()
        }

        applyTheme()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil,
        )
    }

    // MARK: - Theme

    private func applyTheme() {
        let themeManager = ThemeManager.shared
        let theme = themeManager.current
        let hasCustomBackground = themeManager.isColorCustomized(.backgroundColor)
        let hasCustomBorder = themeManager.isColorCustomized(.borderColor)

        backgroundView.effectiveAppearance.performAsCurrentDrawingAppearance {
            // The system material provides the default tint. Explicit user colors remain opaque overrides.
            backgroundView.layer?.backgroundColor = hasCustomBackground
                ? theme.backgroundColor.cgColor
                : NSColor.clear.cgColor
            backgroundView.layer?.borderColor = hasCustomBorder
                ? theme.border.color.cgColor
                : theme.border.color.withAlphaComponent(0.55).cgColor
        }
        backgroundView.layer?.cornerRadius = theme.cornerRadius
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.borderWidth = theme.border.width

        // Clip the panel content to the rounded rect while retaining the native window shadow.
        let contentLayer = panel.contentView?.layer
        contentLayer?.backgroundColor = NSColor.clear.cgColor
        contentLayer?.cornerRadius = theme.cornerRadius
        contentLayer?.masksToBounds = true
    }

    // MARK: - Show / Hide

    /// Displays the candidate grid.
    ///
    /// `candidates` is the full display-capitalised prediction buffer. When `literalText` is non-nil it is prepended
    /// to `candidates` in the unified predictions array so that `predictions[0]` = literal
    /// and `predictions[1…]` = word predictions. The grid starts collapsed (row 0 only).
    func show(
        candidates: [String],
        literalText: String? = nil,
        layout: CandidateLayout = .grid,
        client: (any IMKTextInput)?,
        candidateSelectionHandler: (@MainActor (Int) -> Void)? = nil
    ) {
        guard !candidates.isEmpty || literalText != nil else {
            hide()
            return
        }

        let presentationInterval = PerformanceTrace.signposter.beginInterval("Candidate presentation")
        defer { PerformanceTrace.signposter.endInterval("Candidate presentation", presentationInterval) }

        let unified = literalText.map { [$0] + candidates } ?? candidates
        if literalText != nil, let candidateSelectionHandler {
            candidateView.candidateSelectionHandler = { unifiedIndex in
                guard unifiedIndex > 0 else { return }
                candidateSelectionHandler(unifiedIndex - 1)
            }
        } else {
            candidateView.candidateSelectionHandler = candidateSelectionHandler
        }
        candidateLayout = layout
        // Literal slots are retained for callers that explicitly request one. Normal
        // typing supplies predictions only and therefore starts without a selection.
        hasActiveSelection = literalText != nil
        gridState = GridCandidateState(
            columnCount: layout == .vertical ? 1 : Constants.gridMaxVisibleCols,
            hasLiteral: literalText != nil,
            maxVisibleRows: Constants.gridMaxVisibleRows,
            predictions: unified,
        )
        if layout == .vertical {
            gridState?.isExpanded = true
        }

        if let client {
            panel.level = NSWindow.Level(rawValue: Int(client.windowLevel()) + 1)
        }
        lastCursorRect = PerformanceTrace.measure("Candidate geometry") {
            resolvedCursorRect(from: client)
        }
        PerformanceTrace.measure("Candidate rendering") {
            refreshView()
            let (panelWidth, panelHeight) = fittingPanelSize()
            let origin = clampedPanelOrigin(cursorRect: lastCursorRect, panelWidth: panelWidth, panelHeight: panelHeight)
            presentPanel(at: origin, width: panelWidth, height: panelHeight)
        }
    }

    func hide() {
        panel.orderOut(nil)
        gridState = nil
        hasActiveSelection = false
        candidateView.clearAccessibilityCandidates()
    }

    func performAccessibilityCandidateSelection(at index: Int) -> Bool {
        candidateView.performAccessibilityCandidateSelection(at: index)
    }

    func resetSessionAnchor() {
        lastCursorRect = .zero
        lastValidCursorRect = nil
        cursorClientIdentifier = nil
    }

    // MARK: - Row navigation

    /// Expands the grid (if collapsed) and moves the active row down by one.
    func moveActiveRowDown() {
        if activateSelection() {
            if candidateLayout == .grid {
                mutateGrid({ $0.moveRowDown() }, reframe: true)
            }
            return
        }
        mutateGrid({ $0.moveRowDown() }, reframe: true)
    }

    /// Moves the active row up by one.
    /// Stays expanded when arriving at row 0; collapses on a second press while at row 0.
    func moveActiveRowUp() {
        if activateSelection() { return }
        mutateGrid({ state in
            if candidateLayout == .vertical, state.activeRow == 0 { return }
            state.moveRowUp()
        }, reframe: true)
    }

    // MARK: - Column navigation

    /// Cycles the active column right within the current row (tab / right arrow).
    func moveActiveColumnRight() {
        if activateSelection() { return }
        mutateGrid({ state in
            if candidateLayout == .vertical {
                state.moveRowDown()
            } else {
                state.moveColumnRight()
            }
        }, reframe: false)
    }

    /// Cycles the active column left within the current row (left arrow).
    func moveActiveColumnLeft() {
        if activateSelection() { return }
        mutateGrid({ state in
            if candidateLayout == .vertical {
                if state.activeRow > 0 { state.moveRowUp() }
            } else {
                state.moveColumnLeft()
            }
        }, reframe: false)
    }

    // MARK: - Selection queries

    /// The display-capitalised prediction at the current (activeRow, activeCol) cursor,
    /// or `nil` when the literal slot is selected.
    func selectedCandidate() -> String? {
        guard hasActiveSelection else { return nil }
        return gridState?.selectedPrediction
    }

    /// 0-based prediction index at the current cursor, or `nil` when the literal slot is selected.
    var selectedPredictionIndex: Int? {
        guard hasActiveSelection, let gs = gridState else { return nil }
        return gs.predictionIndex(row: gs.activeRow, col: gs.activeCol)
    }

    /// 0-based prediction index for column `col` of the active row.
    /// Returns `nil` for the literal cell or cells beyond the loaded buffer.
    func predictionIndexAt(gridColumn col: Int) -> Int? {
        guard let gs = gridState else { return nil }
        if candidateLayout == .vertical {
            guard col >= 0, col < gs.renderedRowCount else { return nil }
            return gs.predictionIndex(row: gs.visibleRowOffset + col, col: 0)
        }
        return gs.predictionIndex(row: gs.activeRow, col: col)
    }

    /// True when (activeRow, col) is the literal slot.
    func isLiteralAt(gridColumn col: Int) -> Bool {
        guard let gs = gridState else { return false }
        if candidateLayout == .vertical {
            guard col >= 0, col < gs.renderedRowCount else { return false }
            return gs.hasLiteral && gs.visibleRowOffset + col == 0
        }
        return gs.hasLiteral && gs.activeRow == 0 && col == 0
    }

    /// Activates the logical cursor without advancing past the first candidate.
    @discardableResult
    private func activateSelection() -> Bool {
        guard gridState != nil, !hasActiveSelection else { return false }
        hasActiveSelection = true
        refreshView()
        return true
    }

    // MARK: - Private helpers

    /// Applies a mutation to `gridState` and refreshes the view. When `reframe` is true
    /// the panel is also resized and repositioned (needed after row count changes).
    private func mutateGrid(_ body: (inout GridCandidateState) -> Void, reframe: Bool) {
        guard var gs = gridState else { return }
        body(&gs)
        gridState = gs
        if reframe { refreshViewAndReframe() } else { refreshView() }
    }

    // MARK: - Private rendering

    private func refreshView() {
        guard let gs = gridState else { return }
        candidateView.updateGrid(
            gs,
            layout: candidateLayout,
            showsSelection: hasActiveSelection
        )
    }

    /// Refreshes the view and resizes / repositions the panel to fit the new row count.
    /// Called after any navigation that changes the number of visible rows.
    private func refreshViewAndReframe() {
        refreshView()
        let (panelWidth, panelHeight) = fittingPanelSize()
        let origin = clampedPanelOrigin(cursorRect: lastCursorRect, panelWidth: panelWidth, panelHeight: panelHeight)
        presentPanel(at: origin, width: panelWidth, height: panelHeight)
    }

    private func fittingPanelSize() -> (width: CGFloat, height: CGFloat) {
        candidateView.layoutSubtreeIfNeeded()
        let fittingSize = candidateView.fittingSize
        return (max(fittingSize.width, Layout.minWidth), max(fittingSize.height, Layout.minHeight))
    }

    private func presentPanel(at origin: NSPoint, width: CGFloat, height: CGFloat) {
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
        panel.orderFront(nil)
    }

    private func resolvedCursorRect(from client: (any IMKTextInput)?) -> NSRect {
        if let client {
            let identifier = ObjectIdentifier(client)
            if cursorClientIdentifier != identifier {
                lastValidCursorRect = nil
                cursorClientIdentifier = identifier
            }

            var attributeRect = NSRect.zero
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &attributeRect)
            if let rect = Self.usableCursorRect(attributeRect) {
                lastValidCursorRect = rect
                return rect
            }

            let selection = client.selectedRange()
            if selection.location != NSNotFound {
                var actualRange = NSRange(location: NSNotFound, length: 0)
                let firstRect = client.firstRect(
                    forCharacterRange: NSRange(location: selection.location, length: 0),
                    actualRange: &actualRange
                )
                if let rect = Self.usableCursorRect(firstRect) {
                    lastValidCursorRect = rect
                    return rect
                }
            }

            if let lastValidCursorRect {
                return lastValidCursorRect
            }
        }

        let mouse = NSEvent.mouseLocation
        return NSRect(
            x: mouse.x,
            y: mouse.y - Layout.fallbackLineHeight,
            width: 0,
            height: Layout.fallbackLineHeight
        )
    }

    static func usableCursorRect(_ rect: NSRect) -> NSRect? {
        let standardized = rect.standardized
        let values = [standardized.minX, standardized.minY, standardized.width, standardized.height]
        guard values.allSatisfy(\.isFinite), standardized != .zero, standardized.height > 0 else {
            return nil
        }
        return standardized
    }

    private func clampedPanelOrigin(cursorRect: NSRect, panelWidth: CGFloat, panelHeight: CGFloat) -> NSPoint {
        var origin = NSPoint(
            x: cursorRect.origin.x,
            y: cursorRect.origin.y - panelHeight - Layout.cursorGap,
        )
        let screen = NSScreen.screens.first { $0.frame.contains(cursorRect.origin) }
            ?? NSScreen.main
        if let screen {
            let frame = screen.visibleFrame
            origin.x = min(max(origin.x, frame.minX), frame.maxX - panelWidth)
            if origin.y < frame.minY {
                origin.y = cursorRect.maxY + Layout.cursorGap
            }
            origin.y = min(max(origin.y, frame.minY), frame.maxY - panelHeight)
        }
        return origin
    }

    @objc private func themeDidChange() {
        applyTheme()
        if gridState != nil {
            refreshView()
        }
    }
}
