import AppKit

// MARK: - Highlight Container

@MainActor private final class HighlightContainerView: NSView {
    let label: NSTextField

    var isHighlighted: Bool = false {
        didSet { updateLayerBackground() }
    }

    /// Stored without a `didSet` observer; always set before `isHighlighted`
    /// inside `apply(highlighted:color:radius:)` so the single `didSet` on
    /// `isHighlighted` sees the already-updated color value.
    var highlightColor: NSColor = .clear
    var onAccessibilityPress: (@MainActor () -> Bool)?

    init(label: NSTextField) {
        self.label = label
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates the cell's highlight color, pill radius, and highlighted state in
    /// a single pass. Sets `highlightColor` and `cornerRadius` first so that the
    /// `isHighlighted` `didSet` observer calls `updateLayerBackground()` exactly
    /// once with all values already current.
    func apply(highlighted: Bool, color: NSColor, radius: CGFloat) {
        highlightColor = color
        layer?.cornerRadius = radius
        isHighlighted = highlighted
    }

    override func accessibilityPerformPress() -> Bool {
        onAccessibilityPress?() ?? false
    }

    private func updateLayerBackground() {
        layer?.backgroundColor = isHighlighted && highlightColor.alphaComponent > 0
            ? highlightColor.cgColor
            : nil
    }
}

// MARK: - Candidate View

struct CandidateSpacePresentation {
    let action: DefaultSpaceAction
    let reason: DefaultSpaceReason
    let literalText: String?

    static let none = CandidateSpacePresentation(
        action: .literal,
        reason: .fallbackLiteral,
        literalText: nil
    )
}

private struct PredictionCellPresentation {
    let acceptsSpace: Bool
    let selectionLabel: Int
    let isActive: Bool
    let showNumber: Bool
    let theme: Theme
    let numberAttrs: [NSAttributedString.Key: Any]
}

/// Renders the candidate grid: up to `gridMaxVisibleRows` horizontal rows,
/// each containing up to `maxSupportedGridCols` cells.
///
/// All cells are pre-allocated in `setupView()` and shown/hidden on each `updateGrid` call —
/// no subview additions or removals occur at runtime.
@MainActor final class CandidateView: NSView {
    // MARK: - Grid

    private let gridView: NSGridView
    private let spaceHintLabel = NSTextField(labelWithString: "")
    private var spaceHintHeightConstraint: NSLayoutConstraint!

    /// `cells[r][c]` is the HighlightContainerView for row r, column c.
    private var cells: [[HighlightContainerView]] = []

    /// Thin divider lines between adjacent rows; `separators[i]` sits between row i and row i+1.
    private var separators: [NSView] = []

    // MARK: - Cached theme values — rebuilt only on theme change

    private var wordFont = NSFont.systemFont(ofSize: 14)
    private var numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var baselineOffset: CGFloat = 1.0
    private var pillColor = NSColor.clear
    private var selectedTextColor = NSColor.alternateSelectedControlTextColor
    private var pillRadius: CGFloat = 6
    private var cachedTheme: Theme = .defaultTheme
    private(set) var accessibilityCandidateLabels: [String] = []
    private(set) var accessibilitySelectedCandidateLabel: String?
    private(set) var visualCandidateLabels: [String] = []
    private(set) var spaceHintText: String?
    var candidateSelectionHandler: (@MainActor (Int) -> Void)?
    private var accessibilitySelectionIndex: Int?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        gridView = NSGridView(frame: .zero)
        super.init(frame: frameRect)
        setupView()
        rebuildCachedThemeValues()
        observeThemeChanges()
        configureAccessibility()
    }

    required init?(coder: NSCoder) {
        gridView = NSGridView(frame: .zero)
        super.init(coder: coder)
        setupView()
        rebuildCachedThemeValues()
        observeThemeChanges()
        configureAccessibility()
    }

    // MARK: - Setup

    private func setupView() {
        precondition(
            Constants.maxSupportedGridCols >= (ThemeManager.gridColsOptions.max() ?? 0),
            "CandidateView: maxSupportedGridCols must be >= max(gridColsOptions)",
        )

        let maxRows = Constants.maxSupportedGridRows
        let maxCols = Constants.maxSupportedGridCols

        for _ in 0 ..< maxRows {
            let rowCells: [HighlightContainerView] = (0 ..< maxCols).map { _ in
                let container = HighlightContainerView(label: Self.makeLabelField())
                container.isHidden = true
                container.setAccessibilityElement(true)
                container.setAccessibilityRole(.row)
                container.setAccessibilityHidden(true)
                return container
            }
            cells.append(rowCells)
            let row = gridView.addRow(with: rowCells.map { $0 as NSView })
            row.isHidden = true
            row.topPadding = 0
            row.bottomPadding = 3
        }

        // Each column sizes to its widest visible cell; cells stretch to fill that width.
        // rowSpacing = 0 so hidden rows never contribute unexpected space — the uniform
        // The compact inter-row gap comes from each row's bottomPadding alone.
        gridView.xPlacement = .fill
        gridView.yPlacement = .fill
        gridView.columnSpacing = 2
        gridView.rowSpacing = 0
        gridView.column(at: 0).leadingPadding = 3

        gridView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gridView)

        spaceHintLabel.translatesAutoresizingMaskIntoConstraints = false
        spaceHintLabel.alignment = .right
        spaceHintLabel.lineBreakMode = .byTruncatingTail
        spaceHintLabel.isHidden = true
        spaceHintLabel.setAccessibilityElement(false)
        addSubview(spaceHintLabel)
        spaceHintHeightConstraint = spaceHintLabel.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            gridView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            gridView.bottomAnchor.constraint(equalTo: spaceHintLabel.topAnchor),
            spaceHintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            spaceHintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            spaceHintLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            spaceHintHeightConstraint,
        ])

        // Separators are centred in the compact inter-row gap.
        for rowIndex in 0 ..< maxRows - 1 {
            let separator = NSView()
            separator.wantsLayer = true
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.isHidden = true
            addSubview(separator)
            NSLayoutConstraint.activate([
                separator.heightAnchor.constraint(equalToConstant: 0.5),
                separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                separator.topAnchor.constraint(equalTo: cells[rowIndex][0].bottomAnchor, constant: 1.25),
            ])
            separators.append(separator)
        }
    }

    private static func makeLabelField() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.textColor = .labelColor
        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        label.isHidden = true
        label.setAccessibilityElement(false)
        return label
    }

    private func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("SmartType candidates")
        gridView.setAccessibilityElement(false)
        setAccessibilityRows([])
        setAccessibilityVisibleRows([])
        setAccessibilitySelectedRows([])
        setAccessibilityChildren([])
    }

    // MARK: - Theme observation

    private func observeThemeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil,
        )
    }

    @objc private func themeDidChange() {
        rebuildCachedThemeValues()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuildCachedThemeValues()
        needsDisplay = true
    }

    private func rebuildCachedThemeValues() {
        let theme = ThemeManager.shared.current
        let alpha = ThemeManager.shared.highlightOpacity
        cachedTheme = theme
        wordFont = NSFont.systemFont(ofSize: theme.wordFontSize, weight: theme.fontWeight)
        numberFont = NSFont.monospacedDigitSystemFont(ofSize: theme.numberFontSize, weight: theme.numberFontWeight)
        baselineOffset = (theme.wordFontSize - theme.numberFontSize) / 3.0
        pillRadius = max(theme.cornerRadius - 2, 2)
        var separatorCGColor: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            pillColor = theme.highlightColor.withAlphaComponent(alpha)
            separatorCGColor = ThemeManager.shared.isColorCustomized(.separatorColor)
                ? theme.separatorColor.cgColor
                : theme.separatorColor.withAlphaComponent(0.35).cgColor
        }
        selectedTextColor = alpha >= 0.5 ? theme.highlightTextColor : theme.normalTextColor
        spaceHintLabel.font = numberFont
        spaceHintLabel.textColor = theme.numberLabelColor
        for separator in separators {
            separator.layer?.backgroundColor = separatorCGColor
        }
        for row in cells {
            for cell in row {
                cell.apply(highlighted: cell.isHighlighted, color: pillColor, radius: pillRadius)
                cell.label.needsDisplay = true
            }
        }
    }

    // MARK: - Number label attributes

    private var numberTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: numberFont,
            .foregroundColor: cachedTheme.numberLabelColor,
            .baselineOffset: baselineOffset,
        ]
    }

    /// Returns `base` with its foreground color set to `.clear` when the cell is
    /// not in the active row, hiding the number label on inactive rows.
    private func rowNumberAttrs(_ base: [NSAttributedString.Key: Any], isActiveRow: Bool) -> [NSAttributedString.Key: Any] {
        if isActiveRow { return base }
        var hidden = base
        hidden[.foregroundColor] = NSColor.clear
        return hidden
    }

    // MARK: - Update

    /// Renders the grid described by `state`.
    /// Only `state.renderedRowCount` rows are shown; everything else is hidden.
    func updateGrid(
        _ state: GridCandidateState,
        layout: CandidateLayout = .grid,
        showsSelection: Bool = true,
        spacePresentation: CandidateSpacePresentation = .none
    ) {
        updateSpaceHint(
            action: spacePresentation.action,
            reason: spacePresentation.reason,
            literalText: spacePresentation.literalText
        )
        let theme = cachedTheme
        let numberAttrs = numberTextAttributes
        let renderedRows = state.renderedRowCount
        let columnCount = state.columnCount

        // Show/hide columns; trailing padding on the last visible column provides the right margin.
        for col in 0 ..< Constants.maxSupportedGridCols {
            let column = gridView.column(at: col)
            column.isHidden = col >= columnCount
            column.trailingPadding = col == columnCount - 1 ? 3 : 0
        }

        // Iterate over ALL pre-allocated rows (maxSupportedGridRows), not just the
        // user-configured max (gridMaxVisibleRows). Without this, shrinking from the
        // maximum row count (e.g. 5→3) leaves the excess rows in stale visible state
        // because those indices are never touched by the narrower loop.
        for rowIndex in 0 ..< Constants.maxSupportedGridRows {
            let gridRow = state.visibleRowOffset + rowIndex
            let nsGridRow = gridView.row(at: rowIndex)

            guard rowIndex < renderedRows, gridRow < state.totalRows else {
                nsGridRow.isHidden = true
                hideAllCells(inVisibleRow: rowIndex)
                continue
            }

            nsGridRow.isHidden = false

            for col in 0 ..< columnCount {
                let container = cells[rowIndex][col]
                let isActiveRow = (gridRow == state.activeRow)
                let isActive = showsSelection && isActiveRow && col == state.activeCol
                let selectionLabel = layout == .vertical ? rowIndex + 1 : col + 1
                let showNumber = layout == .vertical || isActiveRow

                if state.hasLiteral, gridRow == 0, col == 0 {
                    renderLiteralCell(
                        container,
                        literalText: state.predictions.first,
                        isActive: isActive,
                        showNumber: showNumber,
                        selectionLabel: selectionLabel,
                        theme: theme,
                        numberAttrs: numberAttrs,
                    )
                } else if let predIdx = state.predictionIndex(row: gridRow, col: col) {
                    renderPredictionCell(
                        container,
                        text: state.predictions[predIdx],
                        predictionIndex: predIdx,
                        presentation: PredictionCellPresentation(
                            acceptsSpace: spacePresentation.action == .prediction(index: predIdx),
                            selectionLabel: selectionLabel,
                            isActive: isActive,
                            showNumber: showNumber,
                            theme: theme,
                            numberAttrs: numberAttrs
                        )
                    )
                } else {
                    hideCell(container)
                }
            }
            for col in columnCount ..< Constants.maxSupportedGridCols {
                hideCell(cells[rowIndex][col])
            }
        }

        for (index, separator) in separators.enumerated() {
            separator.isHidden = layout == .vertical || gridView.row(at: index + 1).isHidden
        }

        synchronizeAccessibility()
    }

    // MARK: - Cell rendering

    private func renderLiteralCell(
        _ container: HighlightContainerView,
        literalText: String?,
        isActive: Bool,
        showNumber: Bool,
        selectionLabel: Int,
        theme: Theme,
        numberAttrs: [NSAttributedString.Key: Any],
    ) {
        let text = literalText ?? ""
        let textColor: NSColor = isActive ? selectedTextColor : theme.normalTextColor
        let quoteAttrs: [NSAttributedString.Key: Any] = [
            .font: wordFont,
            .foregroundColor: theme.numberLabelColor,
        ]

        let activeNumberAttrs = rowNumberAttrs(numberAttrs, isActiveRow: showNumber)

        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: "\(selectionLabel) ", attributes: activeNumberAttrs))
        attributed.append(NSAttributedString(string: "\u{201C}", attributes: quoteAttrs))
        attributed.append(NSAttributedString(string: text, attributes: [
            .font: wordFont,
            .foregroundColor: textColor,
        ]))
        attributed.append(NSAttributedString(string: "\u{201D}", attributes: quoteAttrs))

        container.label.attributedStringValue = attributed
        container.label.isHidden = false
        container.isHidden = false
        configureAccessibilityCell(
            container,
            text: text,
            shortcut: showNumber ? selectionLabel : nil,
            isLiteral: true,
            isSelected: isActive,
            predictionIndex: nil
        )
        container.apply(highlighted: isActive, color: pillColor, radius: pillRadius)
    }

    private func renderPredictionCell(
        _ container: HighlightContainerView,
        text: String,
        predictionIndex: Int,
        presentation: PredictionCellPresentation
    ) {
        let wordColor: NSColor = presentation.isActive
            ? selectedTextColor
            : presentation.theme.normalTextColor
        let activeNumberAttrs = rowNumberAttrs(
            presentation.numberAttrs,
            isActiveRow: presentation.showNumber
        )

        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(
            string: "\(presentation.selectionLabel) ",
            attributes: activeNumberAttrs
        ))
        attributed.append(NSAttributedString(string: text, attributes: [
            .font: wordFont,
            .foregroundColor: wordColor,
        ]))
        if presentation.acceptsSpace {
            appendSpaceKeyIcon(to: attributed)
        }

        container.label.attributedStringValue = attributed
        container.label.isHidden = false
        container.isHidden = false
        configureAccessibilityCell(
            container,
            text: text,
            shortcut: presentation.showNumber ? presentation.selectionLabel : nil,
            isLiteral: false,
            isSelected: presentation.isActive,
            predictionIndex: predictionIndex,
            acceptsSpace: presentation.acceptsSpace
        )
        container.apply(
            highlighted: presentation.isActive,
            color: pillColor,
            radius: pillRadius
        )
    }

}

@MainActor private extension CandidateView {
    func appendSpaceKeyIcon(to attributed: NSMutableAttributedString) {
        attributed.append(NSAttributedString(string: "  "))
        attributed.append(symbolIcon(systemName: "space", fallback: "␣"))
    }

    private func symbolIcon(systemName: String, fallback: String) -> NSAttributedString {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: numberFont.pointSize + 1,
            weight: .regular
        )
        if let image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) {
            image.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = image
            let icon = NSMutableAttributedString(attachment: attachment)
            icon.addAttributes([
                .foregroundColor: cachedTheme.numberLabelColor,
                .baselineOffset: baselineOffset,
            ], range: NSRange(location: 0, length: icon.length))
            return icon
        }
        return NSAttributedString(string: fallback, attributes: [
            .font: numberFont,
            .foregroundColor: cachedTheme.numberLabelColor,
            .baselineOffset: baselineOffset,
        ])
    }

}

// MARK: - Accessibility and cleanup

@MainActor extension CandidateView {
    func performAccessibilityCandidateSelection(at index: Int) -> Bool {
        let visibleCells = cells.flatMap { row in
            row.filter { !$0.isHidden && !$0.label.stringValue.isEmpty }
        }
        guard visibleCells.indices.contains(index) else { return false }
        return visibleCells[index].accessibilityPerformPress()
    }

    func clearAccessibilityCandidates() {
        updateSpaceHint(action: .literal, reason: .fallbackLiteral, literalText: nil)
        for rowIndex in cells.indices {
            gridView.row(at: rowIndex).isHidden = true
            hideAllCells(inVisibleRow: rowIndex)
        }
        accessibilityCandidateLabels = []
        accessibilitySelectedCandidateLabel = nil
        visualCandidateLabels = []
        accessibilitySelectionIndex = nil
        candidateSelectionHandler = nil
        setAccessibilityRows([])
        setAccessibilityVisibleRows([])
        setAccessibilitySelectedRows([])
        setAccessibilityChildren([])
    }

    private func configureAccessibilityCell(
        _ container: HighlightContainerView,
        text: String,
        shortcut: Int?,
        isLiteral: Bool,
        isSelected: Bool,
        predictionIndex: Int?,
        acceptsSpace: Bool = false
    ) {
        let baseDescription = isLiteral ? "literal text, \(text)" : text
        let candidateDescription = acceptsSpace
            ? "\(baseDescription), Space accepts \(text)"
            : baseDescription
        let label = shortcut.map { "\($0), \(candidateDescription)" } ?? candidateDescription
        container.setAccessibilityLabel(label)
        container.setAccessibilitySelected(isSelected)
        container.setAccessibilityHidden(false)
        if let predictionIndex, let candidateSelectionHandler {
            container.onAccessibilityPress = {
                candidateSelectionHandler(predictionIndex)
                return true
            }
        } else {
            container.onAccessibilityPress = nil
        }
    }

    private func synchronizeAccessibility() {
        let visibleCells = cells.flatMap { row in
            row.filter { !$0.isHidden && !$0.label.stringValue.isEmpty }
        }
        for (index, cell) in visibleCells.enumerated() {
            cell.setAccessibilityIndex(index)
        }

        let labels = visibleCells.compactMap { $0.accessibilityLabel() }
        let selectedIndex = visibleCells.firstIndex { $0.isAccessibilitySelected() }
        let selectionChanged = selectedIndex != accessibilitySelectionIndex

        accessibilityCandidateLabels = labels
        accessibilitySelectedCandidateLabel = selectedIndex.map { labels[$0] }
        visualCandidateLabels = visibleCells.map { $0.label.stringValue }
        accessibilitySelectionIndex = selectedIndex
        setAccessibilityRows(visibleCells)
        setAccessibilityVisibleRows(visibleCells)
        setAccessibilitySelectedRows(selectedIndex.map { [visibleCells[$0]] } ?? [])
        setAccessibilityChildren(visibleCells)

        if selectionChanged, selectedIndex != nil {
            NSAccessibility.post(element: self, notification: .selectedRowsChanged)
        }
    }

    // MARK: - Helpers

    private func updateSpaceHint(
        action: DefaultSpaceAction,
        reason: DefaultSpaceReason,
        literalText: String?
    ) {
        guard action == .literal, let literalText, !literalText.isEmpty else {
            spaceHintText = nil
            spaceHintLabel.stringValue = ""
            spaceHintLabel.isHidden = true
            spaceHintHeightConstraint.constant = 0
            setAccessibilityLabel("SmartType candidates")
            return
        }

        let description = reason == .exactCompletion ? "Exact match" : "Keep typed"
        let indicator = NSMutableAttributedString(
            attributedString: symbolIcon(systemName: "checkmark", fallback: "✓")
        )
        indicator.append(NSAttributedString(string: "  \(description)", attributes: [
            .font: numberFont,
            .foregroundColor: cachedTheme.numberLabelColor,
            .baselineOffset: baselineOffset,
        ]))
        spaceHintLabel.attributedStringValue = indicator
        spaceHintText = spaceHintLabel.stringValue
        spaceHintLabel.isHidden = false
        spaceHintHeightConstraint.constant = ceil(numberFont.ascender - numberFont.descender) + 4
        setAccessibilityLabel("SmartType candidates. Space keeps current word. \(description)")
    }

    private func hideCell(_ container: HighlightContainerView) {
        container.label.stringValue = ""
        container.label.isHidden = true
        container.isHidden = true
        container.isHighlighted = false
        container.setAccessibilityLabel(nil)
        container.setAccessibilitySelected(false)
        container.setAccessibilityHidden(true)
        container.onAccessibilityPress = nil
    }

    private func hideAllCells(inVisibleRow rowIndex: Int) {
        for container in cells[rowIndex] {
            hideCell(container)
        }
    }
}
