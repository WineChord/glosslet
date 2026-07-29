import AppKit

@main
enum GlossletMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = GlossletAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
