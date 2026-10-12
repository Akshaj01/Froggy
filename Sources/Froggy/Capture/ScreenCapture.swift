import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenCapture {
    enum Failure: LocalizedError {
        case permission
        case unavailable

        var errorDescription: String? {
            switch self {
            case .permission:
                "Allow Froggy in System Settings → Privacy & Security → Screen Recording."
            case .unavailable:
                "Couldn't take a screenshot."
            }
        }
    }

    static func savePNG(displayID: UInt32, scale: CGFloat, to destination: URL) async throws {
        if !CGPreflightScreenCaptureAccess() && !CGRequestScreenCaptureAccess() {
            throw Failure.permission
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                throw Failure.permission
            }
            throw Failure.unavailable
        }

        let display = content.displays.first { $0.displayID == CGDirectDisplayID(displayID) } ?? content.displays.first
        guard let display else {
            throw Failure.unavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
        configuration.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let image: CGImage
        do {
            image = try await captureImage(filter: filter, configuration: configuration)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                throw Failure.permission
            }
            throw Failure.unavailable
        }

        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw Failure.unavailable
        }
        CGImageDestinationAddImage(imageDestination, image, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw Failure.unavailable
        }
    }

    private static func captureImage(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? Failure.unavailable)
                }
            }
        }
    }
}
