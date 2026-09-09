@testable import SwiftType
import XCTest

@MainActor final class SettingsWindowControllerTests: XCTestCase {
    func testAppearancePaneIncludesCandidatePreview() throws {
        let controller = SettingsWindowController.shared
        controller.selectTab(.customization, animate: false)
        let preview = try XCTUnwrap(controller.candidatePreview)

        XCTAssertFalse(preview.accessibilityCandidateLabels.isEmpty)
    }

    func testSettingsWindowUsesFrameAutosave() throws {
        _ = try XCTUnwrap(SettingsWindowController.shared.window)

        XCTAssertEqual(
            SettingsWindowController.shared.windowFrameAutosaveName,
            SettingsWindowController.frameAutosaveName
        )
    }
}
