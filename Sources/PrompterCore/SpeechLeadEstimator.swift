import Foundation

public enum SpeechLeadEstimator {
    /// Estimates how many words the speaker has likely advanced beyond the last
    /// segment emitted by Apple Speech. This compensates for recognition delay
    /// without moving the aligner's confirmed position.
    public static func leadWords(
        segmentCount: Int,
        lastSegmentEnd: TimeInterval,
        audioElapsed: TimeInterval,
        isFinal: Bool
    ) -> Int {
        guard !isFinal, segmentCount > 0 else { return 0 }
        // On-device partial results almost never carry segment timestamps (4 of
        // 215 in the 2026-10-05 replay). Without them the delay below would be
        // the whole session; one word measured as the unbiased lead.
        guard lastSegmentEnd > 0 else { return 1 }

        let usableDuration = max(0.5, lastSegmentEnd)
        let measuredRate = Double(segmentCount) / usableDuration
        let wordsPerSecond = min(3.4, max(1.7, measuredRate))
        let recognitionDelay = max(0, audioElapsed - lastSegmentEnd)
        // Subtract a tiny epsilon so floating-point noise at an exact word
        // boundary does not add an unnecessary extra word of prediction.
        let estimatedAdvance = Int(ceil(recognitionDelay * wordsPerSecond - 0.000_001))

        // Once a word has ended, the reader is normally already entering the
        // next one. Keep the prediction bounded so a noisy partial cannot jump.
        return min(4, max(1, estimatedAdvance))
    }

    /// Partial hypotheses may lead the confirmed word, but a final hypothesis
    /// is authoritative and must reconcile the visual cursor before the next
    /// recognition session starts.
    public static func displayedIndex(
        currentDisplayedIndex: Int,
        confirmedIndex: Int,
        leadWords: Int,
        lastIndex: Int,
        isFinal: Bool
    ) -> Int {
        let boundedConfirmed = min(max(0, confirmedIndex), max(0, lastIndex))
        if isFinal { return boundedConfirmed }

        let predicted = min(max(0, lastIndex), boundedConfirmed + max(0, leadWords))
        return max(currentDisplayedIndex, predicted)
    }
}
