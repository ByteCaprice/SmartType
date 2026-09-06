import Foundation

/// Mutable composition state for `InputController`.
@MainActor final class InputState {
    var compositionBuffer = ""
    var currentPredictions: [String] = []
    var didAutoInsertTrailingSpace = false
    var mirrorsClientText = false
    var compositionBaseline: NSRange?
    var expectedCursor: Int?
    var compositionClientBundleID: String?
    var autoInsertedSpaceClientBundleID: String?
    var autoInsertedSpaceExpectedCursor: Int?

    func reset() {
        compositionBuffer = ""
        currentPredictions = []
        didAutoInsertTrailingSpace = false
        mirrorsClientText = false
        compositionBaseline = nil
        expectedCursor = nil
        compositionClientBundleID = nil
        autoInsertedSpaceClientBundleID = nil
        autoInsertedSpaceExpectedCursor = nil
    }
}
