import Foundation
#if !PROMPTER_STANDALONE
import PrompterCore
#endif

/// `OfflineReplay <raw.jsonl> <script.txt>` re-runs the cursor on Apple Speech
/// hypotheses recorded by `PrivatePrompter --replay`, printing the same CSV, so
/// alignment changes can be measured without the recognizer or permissions.
@main
enum OfflineReplay {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3,
              let raw = try? String(contentsOfFile: args[1], encoding: .utf8),
              let script = try? String(contentsOfFile: args[2], encoding: .utf8) else {
            FileHandle.standardError.write(Data("usage: OfflineReplay <raw.jsonl> <script.txt>\n".utf8))
            exit(2)
        }
        let tracker = CursorTracker(text: script)
        print("t,confirmed,displayed,lead,final,session")
        for line in raw.split(separator: "\n") {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let t = row["t"] as? Double,
                  let session = row["session"] as? Int,
                  let isFinal = row["final"] as? Bool,
                  let transcript = row["transcript"] as? String,
                  let segments = row["segments"] as? Int,
                  let lastSegmentEnd = row["lastSegmentEnd"] as? Double,
                  let audioElapsed = row["audioElapsed"] as? Double else { continue }
            let lead = SpeechLeadEstimator.leadWords(
                segmentCount: segments,
                lastSegmentEnd: lastSegmentEnd,
                audioElapsed: audioElapsed,
                isFinal: isFinal
            )
            let cursor = tracker.update(transcript: transcript, sessionID: session, leadWords: lead, isFinal: isFinal)
            print(String(format: "%.3f,%d,%d,%d,%d,%d", t, cursor.confirmed, cursor.displayed, lead, isFinal ? 1 : 0, session))
        }
    }
}
