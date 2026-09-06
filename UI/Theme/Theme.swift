import AppKit

@MainActor struct ThemeBorder {
    nonisolated static let standardWidth: CGFloat = 1

    let color: NSColor
    let width: CGFloat
}

@MainActor struct Theme {
    let backgroundColor: NSColor
    let border: ThemeBorder
    let cornerRadius: CGFloat
    let highlightTextColor: NSColor
    let highlightColor: NSColor
    let normalTextColor: NSColor
    let numberLabelColor: NSColor
    let separatorColor: NSColor
    let fontWeight: NSFont.Weight
    let numberFontWeight: NSFont.Weight
    let wordFontSize: CGFloat
    let numberFontSize: CGFloat

    func color(for key: ThemeColorKey) -> NSColor {
        switch key {
        case .backgroundColor: backgroundColor
        case .borderColor: border.color
        case .separatorColor: separatorColor
        case .normalTextColor: normalTextColor
        case .numberLabelColor: numberLabelColor
        case .highlightTextColor: highlightTextColor
        case .highlightColor: highlightColor
        }
    }

    init(
        backgroundColor: NSColor,
        border: ThemeBorder,
        cornerRadius: CGFloat,
        highlightTextColor: NSColor,
        highlightColor: NSColor,
        normalTextColor: NSColor,
        numberLabelColor: NSColor,
        separatorColor: NSColor,
        fontWeight: NSFont.Weight,
        numberFontWeight: NSFont.Weight,
        wordFontSize: CGFloat = 14,
        numberFontSize: CGFloat = 11,
    ) {
        self.backgroundColor = backgroundColor
        self.border = border
        self.cornerRadius = cornerRadius
        self.highlightTextColor = highlightTextColor
        self.highlightColor = highlightColor
        self.normalTextColor = normalTextColor
        self.numberLabelColor = numberLabelColor
        self.separatorColor = separatorColor
        self.fontWeight = fontWeight
        self.numberFontWeight = numberFontWeight
        self.wordFontSize = wordFontSize
        self.numberFontSize = numberFontSize
    }

    /// Semantic colors keep the candidate panel coordinated with the current macOS appearance.
    static let defaultTheme = Theme(
        backgroundColor: .windowBackgroundColor,
        border: ThemeBorder(color: .separatorColor, width: ThemeBorder.standardWidth),
        cornerRadius: 10,
        highlightTextColor: .alternateSelectedControlTextColor,
        highlightColor: .controlAccentColor,
        normalTextColor: .labelColor,
        numberLabelColor: .secondaryLabelColor,
        separatorColor: .separatorColor,
        fontWeight: .regular,
        numberFontWeight: .regular,
    )
}
