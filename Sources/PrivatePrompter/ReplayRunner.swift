import AppKit
import PrompterCore

/// `PrivatePrompter --replay <audio> <script.txt> <out.csv>` feeds a recording
/// through the real speech pipeline in real time and logs where the cursor was,
/// so tracking can be measured against the recording's word timings.
enum ReplayRunner {
    /// The app delegate does not own replay mode, so keep the controller alive
    /// until the file has finished and the CSV has been flushed.
    private static var activeSpeech: SpeechController?

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--replay"), args.count > flag + 3 else { return false }
        let audio = URL(fileURLWithPath: args[flag + 1])
        let script = (try? String(contentsOfFile: args[flag + 2], encoding: .utf8)) ?? ""
        let out = URL(fileURLWithPath: args[flag + 3])

        let speech = SpeechController()
        activeSpeech = speech
        let tracker = CursorTracker(text: script)
        var rows = ["t,confirmed,displayed,lead,final,session"]
        var begin: TimeInterval?
        // Apple's raw hypotheses: `OfflineReplay` re-runs the aligner on them
        // without the recognizer, so tuning needs no new recording or permission.
        var raw: [String] = []

        speech.onTranscript = { update in
            let now = ProcessInfo.processInfo.systemUptime
            let t = now - (begin ?? now)
            let cursor = tracker.update(
                transcript: update.transcript,
                sessionID: update.sessionID,
                leadWords: update.leadWords,
                isFinal: update.isFinal
            )
            let fields: [String: Any] = [
                "t": t, "session": update.sessionID, "final": update.isFinal,
                "transcript": update.transcript, "segments": update.segmentCount,
                "lastSegmentEnd": update.lastSegmentEnd, "audioElapsed": update.audioElapsed,
            ]
            if let line = try? JSONSerialization.data(withJSONObject: fields) {
                raw.append(String(decoding: line, as: UTF8.self))
            }
            rows.append(String(format: "%.3f,%d,%d,%d,%d,%d", t, cursor.confirmed, cursor.displayed, update.leadWords, update.isFinal ? 1 : 0, update.sessionID))
        }
        speech.onStatus = { status in
            rows.append("# \(status)")
            if status == "Replay in corso" { begin = ProcessInfo.processInfo.systemUptime }
        }
        speech.onRunningChanged = { running in
            guard !running else { return }
            try? rows.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
            try? raw.joined(separator: "\n").write(to: out.appendingPathExtension("jsonl"), atomically: true, encoding: .utf8)
            activeSpeech = nil
            NSApp.terminate(nil)
        }
        speech.start(localeIdentifier: "it-IT", contextualWords: tracker.aligner.document.contextualWords, replayURL: audio)
        return true
    }
}
