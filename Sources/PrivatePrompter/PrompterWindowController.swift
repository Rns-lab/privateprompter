import AppKit
import PrompterCore

final class PrompterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClickableTextView: NSTextView {
    var locationHandler: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let layoutManager, let textContainer else {
            super.mouseDown(with: event)
            return
        }

        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        locationHandler?(characterIndex)
    }
}

final class PrompterWindowController: NSWindowController {
    var onWordClicked: ((Int) -> Void)?
    var onToggleListening: (() -> Void)?
    var onCloseRequested: (() -> Void)?

    private let scrollView = NSScrollView()
    private let textView = ClickableTextView()
    private let rootView = NSVisualEffectView()
    private let listenButton = ClosureButton(title: "Ascolta", handler: {})
    private var scriptDocument = ScriptDocument(text: "")
    private var currentIndex = 0
    private var fontSize = UserDefaults.standard.double(forKey: "fontSize")

    init() {
        if fontSize == 0 { fontSize = 34 }

        let savedFrame = UserDefaults.standard.string(forKey: "prompterFrame").map(NSRectFromString)
        let defaultFrame = NSRect(x: 0, y: 0, width: 720, height: 300)
        let panel = PrompterPanel(
            contentRect: savedFrame ?? defaultFrame,
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        configure(panel)
        buildContent()
        if savedFrame == nil { panel.center() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveFrame),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveFrame),
            name: NSWindow.didEndLiveResizeNotification,
            object: panel
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(script: String, currentIndex: Int, captureProtected: Bool) {
        setScript(script, currentIndex: currentIndex)
        setCaptureProtected(captureProtected)
        guard let window else { return }
        window.orderFrontRegardless()
        // AppKit can rewrite window-server attributes while ordering the panel.
        // Reapply capture protection after it is visible.
        setCaptureProtected(captureProtected)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func toggleVisibility(script: String, currentIndex: Int, captureProtected: Bool) {
        if window?.isVisible == true {
            hide()
        } else {
            show(script: script, currentIndex: currentIndex, captureProtected: captureProtected)
        }
    }

    func setCaptureProtected(_ protected: Bool) {
        window?.sharingType = protected ? .none : .readOnly
    }

    func setListening(_ listening: Bool) {
        listenButton.title = listening ? "Pausa" : "Ascolta"
    }

    func setScript(_ text: String, currentIndex: Int = 0) {
        scriptDocument = ScriptDocument(text: text)
        self.currentIndex = min(max(0, currentIndex), max(0, scriptDocument.words.count - 1))
        textView.textStorage?.setAttributedString(baseAttributedString())
        highlightCurrentWord(scroll: true)
    }

    func setCurrentWord(_ index: Int) {
        guard !scriptDocument.words.isEmpty else { return }
        let targetIndex = min(max(0, index), scriptDocument.words.count - 1)
        guard targetIndex != currentIndex else { return }
        updateHighlight(from: currentIndex, to: targetIndex)
        currentIndex = targetIndex
        center(range: scriptDocument.words[targetIndex].range)
    }

    private func configure(_ panel: NSPanel) {
        panel.title = "Private Prompter Overlay"
        panel.appearance = NSAppearance(named: .aqua)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 380, height: 170)
        panel.alphaValue = savedOpacity
    }

    private var savedOpacity: Double {
        let value = UserDefaults.standard.double(forKey: "prompterOpacity")
        return value == 0 ? 0.92 : value
    }

    private func buildContent() {
        guard let window else { return }

        let workspace = NSWorkspace.shared
        let reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        let increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast

        rootView.appearance = NSAppearance(named: .aqua)
        rootView.material = reduceTransparency ? .contentBackground : .popover
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(
            calibratedWhite: 0.90,
            alpha: reduceTransparency ? 1.0 : 0.84
        ).cgColor
        rootView.layer?.borderColor = NSColor(
            calibratedWhite: 0.18,
            alpha: increaseContrast ? 1.0 : 0.86
        ).cgColor
        rootView.layer?.borderWidth = increaseContrast ? 2.5 : 1.5
        rootView.layer?.cornerRadius = 18
        rootView.layer?.masksToBounds = true
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 30, height: 28)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.locationHandler = { [weak self] location in
            guard let self, let index = self.scriptDocument.wordIndex(containingUTF16Location: location) else { return }
            self.onWordClicked?(index)
        }
        scrollView.documentView = textView

        let toolbar = DraggableView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = compactButton("↺") { [weak self] in self?.onWordClicked?(0) }
        listenButton.handler = { [weak self] in self?.onToggleListening?() }
        styleCompactButton(listenButton)
        let smallerButton = compactButton("A−") { [weak self] in self?.changeFont(by: -2) }
        let largerButton = compactButton("A+") { [weak self] in self?.changeFont(by: 2) }
        let closeButton = compactButton("×") { [weak self] in self?.onCloseRequested?() }
        let opacity = ClosureSlider(value: savedOpacity, minValue: 0.35, maxValue: 1) { [weak self] value in
            self?.window?.alphaValue = value
            UserDefaults.standard.set(value, forKey: "prompterOpacity")
        }
        opacity.translatesAutoresizingMaskIntoConstraints = false
        opacity.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let stack = NSStackView(views: [resetButton, listenButton, smallerButton, largerButton, opacity, closeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        rootView.addSubview(scrollView)
        rootView.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: rootView.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 46),

            stack.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 2),

            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
    }

    private func compactButton(_ title: String, handler: @escaping () -> Void) -> ClosureButton {
        let button = ClosureButton(title: title, handler: handler)
        styleCompactButton(button)
        return button
    }

    private func styleCompactButton(_ button: NSButton) {
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = NSColor(calibratedWhite: 0.12, alpha: 1)
    }

    private func baseAttributedString() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineSpacing = max(5, fontSize * 0.22)
        paragraph.paragraphSpacing = max(8, fontSize * 0.35)

        return NSAttributedString(
            string: scriptDocument.text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.07, alpha: 1),
                .paragraphStyle: paragraph,
            ]
        )
    }

    private func highlightCurrentWord(scroll: Bool) {
        guard scriptDocument.words.indices.contains(currentIndex), let storage = textView.textStorage else { return }
        let word = scriptDocument.words[currentIndex]
        let beforeLength = word.range.location

        if beforeLength > 0 {
            storage.addAttribute(
                .foregroundColor,
                value: NSColor(calibratedWhite: 0.16, alpha: 0.52),
                range: NSRange(location: 0, length: beforeLength)
            )
        }

        storage.addAttributes(
            [
                .foregroundColor: NSColor.black,
                .backgroundColor: NSColor(calibratedRed: 0.35, green: 0.72, blue: 1.0, alpha: 0.72),
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            ],
            range: word.range
        )

        if scroll { center(range: word.range, animated: false) }
    }

    private func updateHighlight(from oldIndex: Int, to newIndex: Int) {
        guard
            scriptDocument.words.indices.contains(oldIndex),
            scriptDocument.words.indices.contains(newIndex),
            let storage = textView.textStorage
        else { return }

        let oldWord = scriptDocument.words[oldIndex]
        let newWord = scriptDocument.words[newIndex]
        let regularFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let baseColor = NSColor(calibratedWhite: 0.07, alpha: 1)
        let pastColor = NSColor(calibratedWhite: 0.16, alpha: 0.52)

        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: oldWord.range)
        storage.addAttribute(.font, value: regularFont, range: oldWord.range)

        if newWord.range.location > oldWord.range.location {
            let length = newWord.range.location - oldWord.range.location
            storage.addAttribute(
                .foregroundColor,
                value: pastColor,
                range: NSRange(location: oldWord.range.location, length: length)
            )
        } else {
            let upperBound = NSMaxRange(oldWord.range)
            let length = max(0, upperBound - newWord.range.location)
            if length > 0 {
                storage.addAttribute(
                    .foregroundColor,
                    value: baseColor,
                    range: NSRange(location: newWord.range.location, length: length)
                )
            }
        }

        storage.addAttributes(
            [
                .foregroundColor: NSColor.black,
                .backgroundColor: NSColor(calibratedRed: 0.35, green: 0.72, blue: 1.0, alpha: 0.72),
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            ],
            range: newWord.range
        )
        storage.endEditing()
    }

    private func center(range: NSRange, animated: Bool = true) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        let targetY = min(maxY, max(0, rect.minY + textView.textContainerOrigin.y - clip.bounds.height * 0.38))
        // Same line: don't move, the eye is already there.
        guard abs(clip.bounds.origin.y - targetY) > 1 else { return }

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            clip.setBoundsOrigin(NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(clip)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: targetY))
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    private func changeFont(by delta: Double) {
        fontSize = min(82, max(20, fontSize + delta))
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        textView.textStorage?.setAttributedString(baseAttributedString())
        highlightCurrentWord(scroll: true)
    }

    @objc private func saveFrame() {
        guard let window else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "prompterFrame")
    }
}
