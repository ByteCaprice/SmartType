import AppKit

// MARK: - Customization Tab

extension SettingsWindowController {
    func makeCustomizationTab() -> NSView {
        let container = NSView()

        let stack = makeContentStack()

        stack.addArrangedSubview(makeSectionLabel("Colors"))
        for key in ThemeColorKey.allCases {
            stack.addArrangedSubview(makeColorRow(for: key))
        }
        stack.setCustomSpacing(Layout.sectionSpacing, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(makeSectionLabel("Candidate Window"))
        stack.addArrangedSubview(makeHighlightOpacityRow())
        stack.addArrangedSubview(makeCandidateLayoutRow())
        stack.addArrangedSubview(makeCandidateCountRow())
        stack.addArrangedSubview(makeGridRowsRow())
        stack.setCustomSpacing(Layout.sectionSpacing, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(makeSectionLabel("Preview"))
        stack.addArrangedSubview(makeCandidatePreview())

        container.addSubview(stack)

        let resetButton = NSButton(title: "Reset All Appearance\u{2026}", target: self, action: #selector(confirmAppearanceReset))
        resetButton.bezelStyle = .push
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resetButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.edgeInset),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.edgeInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -Layout.edgeInset),

            resetButton.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: Layout.edgeInset),
            resetButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.edgeInset),
            resetButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.edgeInset),
        ])

        return container
    }

    // MARK: - Row Builders

    private func makeColorRow(for key: ThemeColorKey) -> NSView {
        let color = ThemeManager.shared.current.color(for: key)
        let well = makeColorWell(color: color, action: #selector(colorWellChanged(_:)))
        well.identifier = NSUserInterfaceItemIdentifier(key.rawValue)
        colorWells[key] = well
        return makeSettingsRow(label: key.displayName, control: well)
    }

    private func makeHighlightOpacityRow() -> NSView {
        let initialValue = ThemeManager.shared.highlightOpacity

        highlightOpacitySlider = NSSlider(value: Double(initialValue),
                                          minValue: 0.0,
                                          maxValue: 1.0,
                                          target: self,
                                          action: #selector(highlightOpacityChanged(_:)))
        highlightOpacitySlider.translatesAutoresizingMaskIntoConstraints = false
        highlightOpacitySlider.widthAnchor.constraint(equalToConstant: Layout.sliderWidth).isActive = true
        highlightOpacitySlider.setAccessibilityLabel("Highlight Opacity")
        highlightOpacitySlider.setAccessibilityValue(formatOpacity(initialValue))

        highlightOpacityLabel = NSTextField(labelWithString: formatOpacity(initialValue))
        highlightOpacityLabel.font = .monospacedSystemFont(ofSize: Layout.headerFontSize, weight: .regular)
        highlightOpacityLabel.translatesAutoresizingMaskIntoConstraints = false
        highlightOpacityLabel.widthAnchor.constraint(equalToConstant: Layout.sliderLabelWidth).isActive = true

        let sliderRow = NSStackView(views: [highlightOpacitySlider, highlightOpacityLabel])
        sliderRow.spacing = 4

        return makeSettingsRow(label: "Highlight Opacity", control: sliderRow)
    }

    private func makeCandidateCountRow() -> NSView {
        let index = ThemeManager.gridColsOptions.firstIndex(of: ThemeManager.shared.gridCols) ?? 2
        candidateCountPopUp = makePopUp(items: ThemeManager.gridColsOptions.map(String.init), selectedIndex: index, action: #selector(candidateCountChanged(_:)))
        candidateCountPopUp.isEnabled = ThemeManager.shared.candidateLayout == .grid
        candidateCountPopUp.toolTip = "Applies to Grid layout"
        return makeSettingsRow(label: "Grid Columns", control: candidateCountPopUp)
    }

    private func makeCandidateLayoutRow() -> NSView {
        let layouts = CandidateLayout.allCases
        let index = layouts.firstIndex(of: ThemeManager.shared.candidateLayout) ?? 0
        candidateLayoutPopUp = makePopUp(
            items: layouts.map(\.displayName),
            selectedIndex: index,
            action: #selector(candidateLayoutChanged(_:)),
        )
        return makeSettingsRow(label: "Candidate Layout", control: candidateLayoutPopUp)
    }

    private func makeGridRowsRow() -> NSView {
        let index = ThemeManager.gridRowsOptions.firstIndex(of: ThemeManager.shared.gridRows) ?? 0
        gridRowsPopUp = makePopUp(items: ThemeManager.gridRowsOptions.map(String.init), selectedIndex: index, action: #selector(gridRowsChanged(_:)))
        return makeSettingsRow(label: "Candidate Rows", control: gridRowsPopUp)
    }

    private func makeCandidatePreview() -> NSView {
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = ThemeManager.shared.current.cornerRadius

        let preview = CandidateView(frame: .zero)
        preview.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            preview.topAnchor.constraint(equalTo: background.topAnchor),
            preview.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        candidatePreview = preview
        candidatePreviewBackground = background
        refreshCandidatePreview()
        return background
    }

    // MARK: - Actions

    @objc private func colorWellChanged(_ sender: NSColorWell) {
        guard let key = ThemeColorKey(rawValue: sender.identifier?.rawValue ?? "") else { return }
        ThemeManager.shared.setColor(sender.color.hexString, for: key)
        refreshCandidatePreview()
    }

    @objc private func highlightOpacityChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        ThemeManager.shared.setHighlightOpacity(value)
        highlightOpacityLabel?.stringValue = formatOpacity(value)
        sender.setAccessibilityValue(formatOpacity(value))
        refreshCandidatePreview()
    }

    @objc private func candidateCountChanged(_ sender: NSPopUpButton) {
        let options = ThemeManager.gridColsOptions
        guard sender.indexOfSelectedItem < options.count else { return }
        ThemeManager.shared.setGridCols(options[sender.indexOfSelectedItem])
        refreshCandidatePreview()
    }

    @objc private func candidateLayoutChanged(_ sender: NSPopUpButton) {
        let layouts = CandidateLayout.allCases
        guard sender.indexOfSelectedItem < layouts.count else { return }
        let layout = layouts[sender.indexOfSelectedItem]
        ThemeManager.shared.setCandidateLayout(layout)
        candidateCountPopUp?.isEnabled = layout == .grid
        refreshCandidatePreview()
    }

    @objc private func gridRowsChanged(_ sender: NSPopUpButton) {
        let options = ThemeManager.gridRowsOptions
        guard sender.indexOfSelectedItem < options.count else { return }
        ThemeManager.shared.setGridRows(options[sender.indexOfSelectedItem])
        refreshCandidatePreview()
    }

    @objc private func confirmAppearanceReset() {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset All Appearance Settings?"
        alert.informativeText = "This resets colors, highlight opacity, candidate layout, grid columns, and candidate rows."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            ThemeManager.shared.resetToDefaults()
            self?.syncCustomizationControls()
        }
    }

    // MARK: - Sync

    func syncCustomizationControls() {
        for key in ThemeColorKey.allCases {
            colorWells[key]?.color = ThemeManager.shared.current.color(for: key)
        }

        let opacity = ThemeManager.shared.highlightOpacity
        highlightOpacitySlider?.doubleValue = Double(opacity)
        highlightOpacityLabel?.stringValue = formatOpacity(opacity)
        highlightOpacitySlider?.setAccessibilityValue(formatOpacity(opacity))

        let countIndex = ThemeManager.gridColsOptions.firstIndex(of: ThemeManager.shared.gridCols) ?? 2
        candidateCountPopUp?.selectItem(at: countIndex)

        let layoutIndex = CandidateLayout.allCases.firstIndex(of: ThemeManager.shared.candidateLayout) ?? 0
        candidateLayoutPopUp?.selectItem(at: layoutIndex)
        candidateCountPopUp?.isEnabled = ThemeManager.shared.candidateLayout == .grid

        let rowsIndex = ThemeManager.gridRowsOptions.firstIndex(of: ThemeManager.shared.gridRows) ?? 0
        gridRowsPopUp?.selectItem(at: rowsIndex)
        refreshCandidatePreview()
    }

    private func refreshCandidatePreview() {
        guard let candidatePreview else { return }
        let manager = ThemeManager.shared
        let theme = manager.current
        candidatePreviewBackground?.layer?.cornerRadius = theme.cornerRadius
        candidatePreviewBackground?.layer?.borderWidth = theme.border.width
        candidatePreviewBackground?.layer?.borderColor = theme.border.color.cgColor
        candidatePreviewBackground?.layer?.backgroundColor = manager.isColorCustomized(.backgroundColor)
            ? theme.backgroundColor.cgColor
            : NSColor.clear.cgColor

        let layout = manager.candidateLayout
        var state = GridCandidateState(
            columnCount: layout == .vertical ? 1 : manager.gridCols,
            hasLiteral: false,
            maxVisibleRows: min(2, manager.gridRows),
            predictions: ["Hello", "Help", "Helpful"]
        )
        state.isExpanded = layout == .vertical
        candidatePreview.updateGrid(state, layout: layout, showsSelection: true)
    }

    private func formatOpacity(_ value: CGFloat) -> String {
        "\(Int(round(value * 100)))%"
    }
}
