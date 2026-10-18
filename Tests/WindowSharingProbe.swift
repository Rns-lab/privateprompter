import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let targetPID = Int(CommandLine.arguments[1]) else {
    fputs("usage: WindowSharingProbe <pid>\n", stderr)
    exit(2)
}

let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let matches = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == targetPID }

for window in matches {
    let number = window[kCGWindowNumber as String] as? Int ?? -1
    let name = window[kCGWindowName as String] as? String ?? "(senza titolo)"
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    let sharing = window[kCGWindowSharingState as String] as? Int ?? -1
    print("window=\(number) layer=\(layer) sharing=\(sharing) name=\(name)")
}

if matches.isEmpty {
    fputs("No windows found for PID \(targetPID)\n", stderr)
    exit(1)
}
