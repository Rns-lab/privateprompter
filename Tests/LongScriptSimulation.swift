import Foundation
import Darwin
#if !PROMPTER_STANDALONE
import PrompterCore
#endif

/// Exercises the same tracker used by the app against the user's saved script,
/// without printing or copying its contents. Recognition hypotheses are split
/// into many Apple-Speech-like sessions and include deterministic omissions and
/// small transcription mistakes.
@main
enum LongScriptSimulation {
    static func main() {
        guard CommandLine.arguments.count == 2,
              let text = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) else {
            fail("usage: LongScriptSimulation <script.txt>")
        }

        let document = ScriptDocument(text: text)
        let words = document.words.map(\.text)
        guard words.count >= 24 else { fail("saved script is too short for a sustained test") }

        let tracker = CursorTracker(text: text)
        var sourceIndex = 0
        var sessionID = 1
        var worstLag = 0
        var largestJump = 0
        var previousConfirmed = 0

        while sourceIndex < words.count {
            let sessionLength = min(17 + (sessionID % 5), words.count - sourceIndex)
            var hypothesis: [String] = []

            for offset in 0..<sessionLength {
                let absolute = sourceIndex + offset
                // Model occasional recognizer omissions without inventing text.
                if absolute % 13 != 8 { hypothesis.append(words[absolute]) }

                let cursor = tracker.update(
                    transcript: hypothesis.joined(separator: " "),
                    sessionID: sessionID,
                    leadWords: offset % 4 == 0 ? 1 : 0,
                    isFinal: offset == sessionLength - 1
                )

                let expected = absolute
                worstLag = max(worstLag, max(0, expected - cursor.confirmed))
                largestJump = max(largestJump, max(0, cursor.confirmed - previousConfirmed))
                if cursor.confirmed + 5 < previousConfirmed {
                    fail("unexpected backward jump")
                }
                previousConfirmed = cursor.confirmed
            }

            sourceIndex += sessionLength
            sessionID += 1
        }

        let finalLag = words.count - 1 - tracker.aligner.currentIndex
        guard finalLag <= 5 else { fail("tracker stalled before script end; lag=\(finalLag)") }
        guard worstLag <= 7 else { fail("excessive sustained lag=\(worstLag)") }
        guard largestJump <= 25 else { fail("unsafe forward jump=\(largestJump)") }

        // A click while listening must re-anchor the next recognition session.
        let target = words.count / 2
        tracker.jump(to: target)
        let end = min(words.count, target + 8)
        let clicked = tracker.update(
            transcript: words[target..<end].joined(separator: " "),
            sessionID: sessionID,
            leadWords: 0,
            isFinal: true
        )
        guard clicked.confirmed >= end - 3 else { fail("click re-anchor did not advance") }

        guard SpeechStallDetector.shouldRestart(
            now: 10,
            lastResult: 7,
            lastSpeech: 9.5
        ) else { fail("watchdog missed an active-speech stall") }
        guard !SpeechStallDetector.shouldRestart(
            now: 10,
            lastResult: 7,
            lastSpeech: 7
        ) else { fail("watchdog restarted during silence") }
        guard !SpeechStallDetector.shouldRestart(
            now: 10,
            lastResult: 9,
            lastSpeech: 9.5
        ) else { fail("watchdog restarted too early") }

        print("LongScriptSimulation: OK words=\(words.count) sessions=\(sessionID - 1) worstLag=\(worstLag) largestJump=\(largestJump) finalLag=\(finalLag)")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("LongScriptSimulation: FAILED \(message)\n".utf8))
        exit(1)
    }
}
