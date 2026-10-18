import AppKit
import OSLog
import PrompterCore

final class AppCoordinator: NSObject, EditorWindowControllerDelegate, NSMenuDelegate {
    private let speech = SpeechController()
    private let prompter = PrompterWindowController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let editor: EditorWindowController
    private let tracker: CursorTracker
    private var captureProtected: Bool
    private var localeIdentifier: String
    private let alignmentLogger = Logger(
        subsystem: "com.pietropiga.privateprompter.personal",
        category: "Alignment"
    )

    override init() {
        let defaults = UserDefaults.standard
        let initialScript = defaults.string(forKey: "script") ?? Self.demoScript
        captureProtected = defaults.object(forKey: "captureProtected") == nil
            ? true
            : defaults.bool(forKey: "captureProtected")
        localeIdentifier = defaults.string(forKey: "localeIdentifier") ?? "it-IT"
        tracker = CursorTracker(text: initialScript)
        editor = EditorWindowController(
            script: initialScript,
            captureProtected: captureProtected,
            localeIdentifier: localeIdentifier
        )

        super.init()
        editor.delegate = self
        configureStatusItem()
        wireCallbacks()
    }

    func start() {
        prompter.setCaptureProtected(captureProtected)
        editor.show()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Private Prompter")
            button.image?.isTemplate = true
        }
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func wireCallbacks() {
        speech.onTranscript = { [weak self] update in
            guard let self else { return }
            let cursor = self.tracker.update(
                transcript: update.transcript,
                sessionID: update.sessionID,
                leadWords: update.leadWords,
                isFinal: update.isFinal
            )
            self.prompter.setCurrentWord(cursor.displayed)
            self.alignmentLogger.debug(
                "Alignment session=\(update.sessionID, privacy: .public) confirmed=\(cursor.confirmed, privacy: .public) displayed=\(cursor.displayed, privacy: .public) lead=\(update.leadWords, privacy: .public) final=\(update.isFinal, privacy: .public)"
            )
        }
        speech.onStatus = { [weak self] status in
            self?.editor.setStatus(status)
        }
        speech.onRunningChanged = { [weak self] running in
            self?.editor.setListening(running)
            self?.prompter.setListening(running)
            self?.rebuildMenu()
        }

        prompter.onWordClicked = { [weak self] index in
            guard let self else { return }
            self.prompter.setCurrentWord(self.tracker.jump(to: index))
            // Words heard before the click belong to the old position.
            self.speech.restartRecognition()
        }
        prompter.onToggleListening = { [weak self] in self?.toggleListening() }
        prompter.onCloseRequested = { [weak self] in self?.prompter.hide() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        menu.addItem(item("Apri editor…", action: #selector(showEditor), key: "e"))
        menu.addItem(item("Avvia dagli appunti", action: #selector(startFromClipboard), key: "v"))
        menu.addItem(.separator())

        let visible = prompter.window?.isVisible == true
        menu.addItem(item(visible ? "Nascondi pannello" : "Mostra pannello", action: #selector(togglePanel), key: "p"))
        menu.addItem(item(speech.isRunning ? "Ferma ascolto" : "Avvia ascolto", action: #selector(toggleListeningMenu), key: "l"))

        let privacy = item("Invisibile nelle catture", action: #selector(togglePrivacy), key: "")
        privacy.state = captureProtected ? .on : .off
        menu.addItem(privacy)

        menu.addItem(.separator())
        menu.addItem(item("Esci", action: #selector(quit), key: "q"))
    }

    private func item(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private func syncScript() {
        if tracker.aligner.document.text != editor.scriptText {
            tracker.replaceScript(editor.scriptText)
        }
        prompter.setScript(editor.scriptText, currentIndex: tracker.displayedIndex)
    }

    private func beginListening() {
        guard !editor.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            editor.setStatus("Inserisci prima un copione")
            editor.show()
            return
        }

        syncScript()
        // Resume from where the reader was last confirmed, not from a stale prediction.
        tracker.jump(to: tracker.aligner.currentIndex)
        prompter.show(script: editor.scriptText, currentIndex: tracker.displayedIndex, captureProtected: captureProtected)
        speech.start(
            localeIdentifier: localeIdentifier,
            contextualWords: tracker.aligner.document.contextualWords
        )
    }

    private func toggleListening() {
        speech.isRunning ? speech.stop() : beginListening()
    }

    @objc private func showEditor() {
        editor.show()
    }

    @objc private func startFromClipboard() {
        editorRequestedLoadFromClipboard()
        beginListening()
    }

    @objc private func togglePanel() {
        prompter.toggleVisibility(
            script: editor.scriptText,
            currentIndex: tracker.displayedIndex,
            captureProtected: captureProtected
        )
    }

    @objc private func toggleListeningMenu() {
        toggleListening()
    }

    @objc private func togglePrivacy() {
        captureProtected.toggle()
        UserDefaults.standard.set(captureProtected, forKey: "captureProtected")
        editor.setPrivacy(captureProtected)
        prompter.setCaptureProtected(captureProtected)
        rebuildMenu()
    }

    @objc private func quit() {
        speech.stop()
        NSApp.terminate(nil)
    }

    func editorDidChangeScript(_ text: String) {
        if speech.isRunning {
            speech.stop()
            editor.setStatus("Copione aggiornato · premi Mostra e ascolta per ripartire")
        }
        tracker.replaceScript(text)
        prompter.setScript(text)
    }

    func editorRequestedLoadFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            editor.setStatus("Gli appunti non contengono testo")
            return
        }
        editor.setScriptFromOutside(text)
        editor.setStatus("Copione caricato dagli appunti")
    }

    func editorRequestedShowPanel() {
        guard !editor.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            editor.setStatus("Inserisci prima un copione")
            return
        }
        syncScript()
        prompter.show(
            script: editor.scriptText,
            currentIndex: tracker.displayedIndex,
            captureProtected: captureProtected
        )
        editor.setStatus(captureProtected ? "Pannello visibile solo a te" : "Pannello visibile anche nelle catture")
    }

    func editorRequestedStart() {
        beginListening()
    }

    func editorRequestedStop() {
        speech.stop()
    }

    func editorPrivacyChanged(_ enabled: Bool) {
        captureProtected = enabled
        UserDefaults.standard.set(enabled, forKey: "captureProtected")
        prompter.setCaptureProtected(enabled)
        rebuildMenu()
    }

    func editorLocaleChanged(_ identifier: String) {
        localeIdentifier = identifier
        UserDefaults.standard.set(identifier, forKey: "localeIdentifier")
        editor.setStatus("Lingua aggiornata; riparti per applicarla")
        if speech.isRunning {
            speech.stop()
        }
    }

    private static let demoScript = """
    Questo è Private Prompter.

    Premi “Mostra e ascolta”, autorizza il microfono e inizia a leggere. Il testo seguirà la tua voce direttamente sul Mac.

    Il pannello resta davanti alle altre applicazioni ma, con la protezione attiva, non viene incluso nelle condivisioni dello schermo e nelle registrazioni.

    Puoi cliccare qualsiasi parola per ripartire esattamente da quel punto.
    """
}
