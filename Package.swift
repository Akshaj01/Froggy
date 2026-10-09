// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Froggy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Froggy",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreText"),
            ]
        )
    ]
)
