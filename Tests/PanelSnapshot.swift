import AppKit
import Foundation
import PrompterCore

guard CommandLine.arguments.count == 2 else {
    fputs("usage: PanelSnapshot <output.png>\n", stderr)
    exit(2)
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

let controller = PrompterWindowController()
controller.show(
    script: "Ottimo, vorrei parlare di questo oggi. Il testo deve restare nitido e leggibile.",
    currentIndex: 0,
    captureProtected: false
)

RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))

guard
    let view = controller.window?.contentView,
    let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
else {
    fputs("unable to create bitmap representation\n", stderr)
    exit(1)
}

view.cacheDisplay(in: view.bounds, to: representation)
guard let data = representation.representation(using: .png, properties: [:]) else {
    fputs("unable to encode PNG\n", stderr)
    exit(1)
}

try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print(CommandLine.arguments[1])
