import Foundation
@testable import SwiftType
import XCTest

@MainActor final class UninstallTests: XCTestCase {
    private let appBundle = URL(fileURLWithPath: "/test/home/Library/Input Methods/SwiftType.app")
    private let applicationsLink = URL(fileURLWithPath: "/Applications/SwiftType.app")

    func testMissingItemsAreAlreadySuccessfullyUninstalled() {
        let fileManager = FakeUninstallFileManager()

        let result = SettingsWindowController.removeInstallation(
            appBundle: appBundle,
            applicationsSymlink: applicationsLink,
            fileManager: fileManager
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(result.removedAppBundle)
        XCTAssertFalse(result.removedApplicationsLink)
        XCTAssertFalse(result.appBundleRemovalAttempted)
        XCTAssertTrue(fileManager.removedPaths.isEmpty)
    }

    func testExistingBundleAndApplicationsLinkAreRemoved() {
        let fileManager = FakeUninstallFileManager()
        fileManager.existingPaths = [appBundle.path]
        fileManager.symbolicLinks = [applicationsLink.path]

        let result = SettingsWindowController.removeInstallation(
            appBundle: appBundle,
            applicationsSymlink: applicationsLink,
            fileManager: fileManager
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.removedAppBundle)
        XCTAssertTrue(result.removedApplicationsLink)
        XCTAssertTrue(result.appBundleRemovalAttempted)
        XCTAssertEqual(fileManager.removedPaths, [applicationsLink.path, appBundle.path])
    }

    func testRemovalFailuresAreReportedWithoutHidingPartialSuccess() {
        let fileManager = FakeUninstallFileManager()
        fileManager.existingPaths = [appBundle.path]
        fileManager.symbolicLinks = [applicationsLink.path]
        fileManager.failingPaths = [applicationsLink.path]

        let result = SettingsWindowController.removeInstallation(
            appBundle: appBundle,
            applicationsSymlink: applicationsLink,
            fileManager: fileManager
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.removedAppBundle)
        XCTAssertFalse(result.removedApplicationsLink)
        XCTAssertFalse(result.appBundleRemovalAttempted)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].contains(applicationsLink.path))
        XCTAssertEqual(fileManager.removedPaths, [])
    }

    func testBundleRemovalFailureRequiresTermination() {
        let fileManager = FakeUninstallFileManager()
        fileManager.existingPaths = [appBundle.path]
        fileManager.failingPaths = [appBundle.path]

        let result = SettingsWindowController.removeInstallation(
            appBundle: appBundle,
            applicationsSymlink: applicationsLink,
            fileManager: fileManager
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.appBundleRemovalAttempted)
        XCTAssertFalse(result.removedAppBundle)
        XCTAssertEqual(result.failures.count, 1)
    }
}

private final class FakeUninstallFileManager: UninstallFileManaging {
    var existingPaths = Set<String>()
    var symbolicLinks = Set<String>()
    var failingPaths = Set<String>()
    private(set) var removedPaths: [String] = []

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func destinationOfSymbolicLink(atPath path: String) throws -> String {
        guard symbolicLinks.contains(path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return "/test/home/Library/Input Methods/SwiftType.app"
    }

    func removeItem(at url: URL) throws {
        if failingPaths.contains(url.path) {
            throw CocoaError(.fileWriteNoPermission)
        }
        removedPaths.append(url.path)
    }
}
