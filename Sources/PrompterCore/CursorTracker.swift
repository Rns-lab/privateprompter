import Foundation

/// Turns Apple Speech hypotheses into the word shown to the reader: the
/// aligner's confirmed position plus the latency lead of partial results.
public final class CursorTracker {
    public let aligner: VoiceAligner
    public private(set) var displayedIndex = 0

    public init(text: String) {
        aligner = VoiceAligner(text: text)
    }

    public func update(transcript: String, sessionID: Int, leadWords: Int, isFinal: Bool) -> (confirmed: Int, displayed: Int) {
        let confirmed = aligner.align(transcript: transcript, sessionID: sessionID)
        displayedIndex = SpeechLeadEstimator.displayedIndex(
            currentDisplayedIndex: displayedIndex,
            confirmedIndex: confirmed,
            leadWords: leadWords,
            lastIndex: max(0, aligner.document.words.count - 1),
            isFinal: isFinal
        )
        return (confirmed, displayedIndex)
    }

    @discardableResult
    public func jump(to index: Int) -> Int {
        displayedIndex = aligner.jump(to: index)
        return displayedIndex
    }

    public func replaceScript(_ text: String) {
        aligner.replaceScript(text)
        displayedIndex = aligner.currentIndex
    }
}
