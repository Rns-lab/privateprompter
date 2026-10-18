import AppKit

protocol EditorWindowControllerDelegate: AnyObject {
    func editorDidChangeScript(_ text: String)
    func editorRequestedLoadFromClipboard()
    func editorRequestedShowPanel()
    func editorRequestedStart()
    func editorRequestedStop()
    func editorPrivacyChanged(_ enabled: Bool)
    func editorLocaleChanged(_ identifier: String)
}

final class EditorWindowController: NSWindowController, NSTextViewDelegate {
    weak var delegate: EditorWindowControllerDelegate?

    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "Pronto")
    private let startButton = ClosureButton(title: "Mostra e ascolta", handler: {})
    private let privacyCheckbox = NSButton(checkboxWithTitle: "Invisibile in condivisioni e registrazioni", target: nil, action: nil)
    private let localePopup = NSPopUpButton()
    private var isListening = false

    var scriptText: String {
        get { textView.string }
        set { textView.string = newValue }
    }

    var captureProtected: Bool {
        privacyCheckbox.state == .on
    }

    var localeIdentifier: String {
        localePopup.selectedItem?.representedObject as? String ?? "it-IT"
    }

    init(script: String, captureProtected: Bool, localeIdentifier: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Private Prompter"
        window.minSize = NSSize(width: 600, height: 430)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        buildContent(script: script, captureProtected: captureProtected, localeIdentifier: localeIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func setListening(_ listening: Bool) {
        isListening = listening
        startButton.title = listening ? "Ferma ascolto" : "Mostra e ascolta"
    }

    func setStatus(_ status: String) {
        statusLabel.stringValue = status
    }

    func setPrivacy(_ enabled: Bool) {
        privacyCheckbox.state = enabled ? .on : .off
    }

    func setScriptFromOutside(_ script: String) {
        scriptText = script
        UserDefaults.standard.set(script, forKey: "script")
        delegate?.editorDidChangeScript(script)
    }

    private func buildContent(script: String, captureProtected: Bool, localeIdentifier: String) {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Il tuo copione")
        title.font = .systemFont(ofSize: 24, weight: .bold)

        let subtitle = NSTextField(labelWithString: "La voce viene elaborata sul Mac. Clicca una parola nel pannello per ripartire da lì.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 13)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.string = script
        textView.delegate = self
        textView.font = .systemFont(ofSize: 18)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        let clipboardButton = ClosureButton(title: "Carica dagli appunti") { [weak self] in
            self?.delegate?.editorRequestedLoadFromClipboard()
        }
        clipboardButton.bezelStyle = .rounded

        let showButton = ClosureButton(title: "Mostra pannello") { [weak self] in
            self?.delegate?.editorRequestedShowPanel()
        }
        showButton.bezelStyle = .rounded

        startButton.handler = { [weak self] in
            guard let self else { return }
            self.isListening ? self.delegate?.editorRequestedStop() : self.delegate?.editorRequestedStart()
        }
        startButton.bezelStyle = .rounded

        privacyCheckbox.state = captureProtected ? .on : .off
        privacyCheckbox.target = self
        privacyCheckbox.action = #selector(privacyChanged)

        localePopup.addItem(withTitle: "Italiano")
        localePopup.lastItem?.representedObject = "it-IT"
        localePopup.addItem(withTitle: "English")
        localePopup.lastItem?.representedObject = "en-US"
        localePopup.addItem(withTitle: "Sistema")
        localePopup.lastItem?.representedObject = Locale.autoupdatingCurrent.identifier
        if let index = localePopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == localeIdentifier }) {
            localePopup.selectItem(at: index)
        }
        localePopup.target = self
        localePopup.action = #selector(localeChanged)

        let languageLabel = NSTextField(labelWithString: "Lingua voce:")
        languageLabel.textColor = .secondaryLabelColor

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let languageStack = NSStackView(views: [languageLabel, localePopup])
        languageStack.orientation = .horizontal
        languageStack.alignment = .centerY
        languageStack.spacing = 8

        func flexibleSpacer() -> NSView {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return spacer
        }

        let settingsRow = NSStackView(views: [clipboardButton, privacyCheckbox, flexibleSpacer(), languageStack])
        settingsRow.orientation = .horizontal
        settingsRow.alignment = .centerY
        settingsRow.spacing = 14

        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let actionRow = NSStackView(views: [statusLabel, flexibleSpacer(), showButton, startButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 12

        settingsRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [title, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 5
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(headerStack)
        content.addSubview(scrollView)
        content.addSubview(settingsRow)
        content.addSubview(actionRow)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            headerStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),

            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: settingsRow.topAnchor, constant: -18),

            settingsRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            settingsRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            actionRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            actionRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            actionRow.topAnchor.constraint(equalTo: settingsRow.bottomAnchor, constant: 12),
            actionRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
        ])
    }

    func textDidChange(_ notification: Notification) {
        UserDefaults.standard.set(scriptText, forKey: "script")
        delegate?.editorDidChangeScript(scriptText)
    }

    @objc private func privacyChanged() {
        delegate?.editorPrivacyChanged(captureProtected)
    }

    @objc private func localeChanged() {
        delegate?.editorLocaleChanged(localeIdentifier)
    }
}
