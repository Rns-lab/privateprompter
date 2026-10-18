import AVFoundation
import Foundation
import OSLog
import PrompterCore
import Speech

struct SpeechUpdate {
    let transcript: String
    let leadWords: Int
    let isFinal: Bool
    let sessionID: Int
    // Raw timing, kept so a replay can be re-aligned offline.
    let segmentCount: Int
    let lastSegmentEnd: TimeInterval
    let audioElapsed: TimeInterval
}

/// The microphone (or a replayed file) stays open for the whole listening
/// period; only the Apple Speech request is swapped when a session ends, so no
/// audio is lost at session boundaries.
final class SpeechController: NSObject {
    var onTranscript: ((SpeechUpdate) -> Void)?
    var onStatus: ((String) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var shouldBeRunning = false
    private var localeIdentifier = "it-IT"
    private var contextualWords: [String] = []
    private var replayURL: URL?
    private var sessionStartUptime: TimeInterval?
    private var recognitionGeneration = 0
    private var restartWorkItem: DispatchWorkItem?
    private var watchdog: DispatchSourceTimer?
    private let logger = Logger(subsystem: "com.pietropiga.privateprompter.personal", category: "Speech")

    // Touched from the audio thread: guarded by `lock`.
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var lastResultUptime: TimeInterval = 0
    private var lastSpeechUptime: TimeInterval = 0
    private var noiseFloor: Float = 0.002

    var isRunning: Bool { shouldBeRunning }

    /// `replayURL` feeds an audio file in real time instead of the microphone
    /// (offline accuracy test, see `ReplayRunner`).
    func start(localeIdentifier: String, contextualWords: [String], replayURL: URL? = nil) {
        guard !shouldBeRunning else { return }
        self.localeIdentifier = localeIdentifier
        self.contextualWords = Array(contextualWords.prefix(100))
        self.replayURL = replayURL
        shouldBeRunning = true
        onRunningChanged?(true)
        onStatus?("Richiesta autorizzazioni…")
        requestPermissionsAndStart()
    }

    func stop() {
        guard shouldBeRunning else { return }
        shouldBeRunning = false
        endRecognition()
        stopAudio()
        onRunningChanged?(false)
        onStatus?("In pausa")
    }

    /// Starts a fresh recognition session without touching the microphone,
    /// e.g. after the reader clicked a different word.
    func restartRecognition() {
        guard shouldBeRunning, task != nil else { return }
        endRecognition()
        startRecognition()
    }

    private func requestPermissionsAndStart() {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            guard let self else { return }
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { self.fail("Riconoscimento vocale non autorizzato") }
                return
            }
            if self.replayURL != nil {
                DispatchQueue.main.async { self.startEverything() }
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                DispatchQueue.main.async { self.startEverything() }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        granted ? self.startEverything() : self.fail("Microfono non autorizzato")
                    }
                }
            default:
                DispatchQueue.main.async { self.fail("Microfono non autorizzato") }
            }
        }
    }

    private func startEverything() {
        guard shouldBeRunning else { return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            fail("Lingua non supportata da Apple Speech")
            return
        }
        guard recognizer.isAvailable else {
            fail("Riconoscimento vocale non disponibile")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            fail("Modello on-device non disponibile per questa lingua")
            return
        }
        self.recognizer = recognizer

        // The request must exist before audio flows, or the first words are dropped.
        startRecognition()
        guard shouldBeRunning else { return }

        if let replayURL {
            startReplay(replayURL)
        } else {
            startMicrophone()
        }
    }

    // MARK: Audio

    private func startMicrophone() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("Nessun ingresso audio disponibile")
            return
        }

        if tapInstalled { inputNode.removeTap(onBus: 0) }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleAudio(buffer)
        }
        tapInstalled = true

        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: audioEngine)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioConfigurationChanged),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            fail("Impossibile avviare il microfono: \(error.localizedDescription)")
            return
        }
        onStatus?("In ascolto · tutto sul Mac")
    }

    private func stopAudio() {
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: audioEngine)
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// AirPods connected, Zoom grabbing the microphone, sample-rate change:
    /// AVAudioEngine stops itself and the old tap format is invalid.
    @objc private func audioConfigurationChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shouldBeRunning, self.replayURL == nil else { return }
            self.logger.info("Audio configuration changed, restarting input")
            self.stopAudio()
            self.endRecognition()
            self.startRecognition()
            self.startMicrophone()
        }
    }

    private func startReplay(_ url: URL) {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            fail("File audio non leggibile: \(error.localizedDescription)")
            return
        }
        onStatus?("Replay in corso")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 20)  // 50 ms, like a live tap
            let chunkDuration = Double(chunk) / file.processingFormat.sampleRate
            let begin = ProcessInfo.processInfo.systemUptime
            var sent = 0.0
            while let self, self.shouldBeRunning {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                      (try? file.read(into: buffer, frameCount: chunk)) != nil,
                      buffer.frameLength > 0 else { break }
                self.handleAudio(buffer)
                sent += chunkDuration
                let wait = begin + sent - ProcessInfo.processInfo.systemUptime
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.stop() }
        }
    }

    private func handleAudio(_ buffer: AVAudioPCMBuffer) {
        let level = Self.rmsLevel(buffer)
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        // Slow-rising, fast-falling floor: fans and room tone are not speech.
        noiseFloor = level < noiseFloor ? level : noiseFloor + (level - noiseFloor) * 0.002
        if level > max(0.004, noiseFloor * 3) { lastSpeechUptime = now }
        let request = self.request
        lock.unlock()
        request?.append(buffer)
    }

    private static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in stride(from: 0, to: count, by: 4) { sum += channel[index] * channel[index] }
        return (sum / Float((count + 3) / 4)).squareRoot()
    }

    // MARK: Recognition

    private func startRecognition() {
        guard shouldBeRunning, let recognizer else { return }

        recognitionGeneration += 1
        let generation = recognitionGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        request.contextualStrings = contextualWords

        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        self.request = request
        lastResultUptime = now
        lock.unlock()
        sessionStartUptime = now

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handle(result: result, error: error, generation: generation)
            }
        }
        startWatchdog(for: generation)
        logger.info("Speech session started generation=\(generation, privacy: .public)")
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, generation: Int) {
        guard shouldBeRunning, generation == recognitionGeneration else { return }

        if let result {
            lock.lock()
            lastResultUptime = ProcessInfo.processInfo.systemUptime
            lock.unlock()

            let transcription = result.bestTranscription
            let lastSegmentEnd = transcription.segments.last.map { $0.timestamp + $0.duration } ?? 0
            let audioElapsed = sessionStartUptime.map { ProcessInfo.processInfo.systemUptime - $0 } ?? lastSegmentEnd
            let leadWords = SpeechLeadEstimator.leadWords(
                segmentCount: transcription.segments.count,
                lastSegmentEnd: lastSegmentEnd,
                audioElapsed: audioElapsed,
                isFinal: result.isFinal
            )
            onTranscript?(
                SpeechUpdate(
                    transcript: transcription.formattedString,
                    leadWords: leadWords,
                    isFinal: result.isFinal,
                    sessionID: generation,
                    segmentCount: transcription.segments.count,
                    lastSegmentEnd: lastSegmentEnd,
                    audioElapsed: audioElapsed
                )
            )
        }

        if error != nil || result?.isFinal == true {
            logger.info("Speech session ended generation=\(generation, privacy: .public) error=\(error != nil, privacy: .public)")
            let lived = ProcessInfo.processInfo.systemUptime - (sessionStartUptime ?? 0)
            endRecognition()
            // A recognizer that fails instantly would otherwise spin.
            scheduleRecognitionRestart(after: error != nil && lived < 1 ? 0.5 : 0)
        }
    }

    private func scheduleRecognitionRestart(after delay: TimeInterval) {
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.shouldBeRunning, self.task == nil else { return }
            self.startRecognition()
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func endRecognition() {
        recognitionGeneration += 1
        restartWorkItem?.cancel()
        restartWorkItem = nil
        watchdog?.cancel()
        watchdog = nil
        lock.lock()
        let request = self.request
        self.request = nil
        lock.unlock()
        request?.endAudio()
        task?.cancel()
        task = nil
        sessionStartUptime = nil
    }

    /// Apple Speech occasionally stops emitting results while audio is still
    /// flowing; a fresh request recovers it.
    private func startWatchdog(for generation: Int) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self, self.shouldBeRunning, generation == self.recognitionGeneration else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.lock.lock()
            let lastResult = self.lastResultUptime
            let lastSpeech = self.lastSpeechUptime
            self.lock.unlock()

            if SpeechStallDetector.shouldRestart(
                now: now,
                lastResult: lastResult,
                lastSpeech: lastSpeech
            ) {
                self.logger.error("Speech watchdog restart generation=\(generation, privacy: .public)")
                self.restartRecognition()
            }
        }
        watchdog = timer
        timer.resume()
    }

    private func fail(_ message: String) {
        shouldBeRunning = false
        endRecognition()
        stopAudio()
        onRunningChanged?(false)
        onStatus?(message)
    }
}
