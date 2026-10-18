import AppKit

final class ClosureButton: NSButton {
    var handler: (() -> Void)?

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(runHandler)
    }

    @objc private func runHandler() {
        handler?()
    }
}

final class ClosureSlider: NSSlider {
    var handler: ((Double) -> Void)?

    convenience init(value: Double, minValue: Double, maxValue: Double, handler: @escaping (Double) -> Void) {
        self.init(value: value, minValue: minValue, maxValue: maxValue, target: nil, action: nil)
        self.handler = handler
        target = self
        action = #selector(runHandler)
    }

    @objc private func runHandler() {
        handler?(doubleValue)
    }
}

final class DraggableView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
