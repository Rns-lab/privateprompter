import Foundation

/// Pure watchdog policy shared by the live recognizer and regression tests.
/// A restart is justified only while fresh speech is reaching the audio tap
/// and Apple Speech has stopped producing hypotheses for long enough.
public enum SpeechStallDetector {
    public static func shouldRestart(
        now: TimeInterval,
        lastResult: TimeInterval,
        lastSpeech: TimeInterval,
        resultTimeout: TimeInterval = 2.5,
        speechFreshness: TimeInterval = 1.0
    ) -> Bool {
        guard lastResult > 0, lastSpeech > 0 else { return false }
        return now - lastResult > resultTimeout && now - lastSpeech < speechFreshness
    }
}
