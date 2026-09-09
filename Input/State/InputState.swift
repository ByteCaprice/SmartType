import Foundation

/// A prediction presentation tied to the exact composition buffer that produced it.
struct PredictionSnapshot: Equatable, Sendable {
    let buffer: String
    let predictions: [String]
    let defaultSpaceAction: DefaultSpaceAction
    let reason: DefaultSpaceReason
}

/// Mutable composition state for `InputController`.
@MainActor final class InputState {
    var compositionBuffer = ""
    var predictionSnapshot: PredictionSnapshot?
    var currentPredictions: [String] {
        get { predictionSnapshot?.predictions ?? [] }
        set {
            predictionSnapshot = PredictionSnapshot(
                buffer: compositionBuffer,
                predictions: newValue,
                defaultSpaceAction: .literal,
                reason: .fallbackLiteral
            )
        }
    }
    var didAutoInsertTrailingSpace = false
    var mirrorsClientText = false
    var compositionBaseline: NSRange?
    var expectedCursor: Int?
    var compositionClientBundleID: String?
    var autoInsertedSpaceClientBundleID: String?
    var autoInsertedSpaceExpectedCursor: Int?

    func reset() {
        compositionBuffer = ""
        predictionSnapshot = nil
        didAutoInsertTrailingSpace = false
        mirrorsClientText = false
        compositionBaseline = nil
        expectedCursor = nil
        compositionClientBundleID = nil
        autoInsertedSpaceClientBundleID = nil
        autoInsertedSpaceExpectedCursor = nil
    }
}
