// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PrivatePrompter",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PrompterCore", targets: ["PrompterCore"]),
        .executable(name: "PrivatePrompter", targets: ["PrivatePrompter"]),
    ],
    targets: [
        .target(name: "PrompterCore"),
        .executableTarget(
            name: "PrivatePrompter",
            dependencies: ["PrompterCore"]
        ),
        .testTarget(
            name: "PrompterCoreTests",
            dependencies: ["PrompterCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
