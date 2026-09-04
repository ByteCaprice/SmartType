import Foundation
import XCTest

final class PrivacyLoggingTests: XCTestCase {
    func testProductionLogsContainOnlyStaticMessages() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcePaths = ["App", "Input", "Prediction", "Rules", "UI"]
        let fileManager = FileManager.default
        var swiftFiles = [repositoryRoot.appendingPathComponent("main.swift")]

        for path in sourcePaths {
            let directory = repositoryRoot.appendingPathComponent(path)
            let enumerator = try XCTUnwrap(fileManager.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL)
            }
        }

        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("Log.")
            {
                let message = "\(fileURL.lastPathComponent):\(index + 1)"
                XCTAssertFalse(line.contains(#"\("#), "Dynamic log content is forbidden at \(message)")
                XCTAssertTrue(line.trimmingCharacters(in: .whitespaces).hasSuffix(")"),
                              "Log calls must stay on one line at \(message)")
            }
        }
    }
}
