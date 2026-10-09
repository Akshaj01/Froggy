import AppKit

@main
enum FroggyMain {
    static func main() {
        MainActor.assumeIsolated {
            if CommandLine.arguments.contains("--self-test") {
                exit(FroggySelfTest.run())
            }
            let delegate = AppDelegate()
            let application = NSApplication.shared
            application.delegate = delegate
            application.setActivationPolicy(.accessory)
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
    }
}
