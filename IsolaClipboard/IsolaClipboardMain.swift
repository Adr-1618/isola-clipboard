import AppKit

@main
@MainActor
struct IsolaClipboardMain {
    private static let retainedDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = retainedDelegate
        application.run()
    }
}
