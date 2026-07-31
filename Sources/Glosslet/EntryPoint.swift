import AppKit

@main
enum GlossletMain {
    @MainActor
    static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        if let bundleIdentifier = diagnosticBundleIdentifier(
            in: arguments
        ) {
            printSelectionDiagnostic(bundleIdentifier: bundleIdentifier)
            return
        }
        if arguments.contains("--diagnose-selection") {
            printSelectionDiagnostic(bundleIdentifier: nil)
            return
        }

        let application = NSApplication.shared
        let delegate = GlossletAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    private static func diagnosticBundleIdentifier(
        in arguments: [String]
    ) -> String? {
        guard
            let optionIndex = arguments.firstIndex(
                of: "--diagnose-selection-app"
            ),
            arguments.indices.contains(optionIndex + 1)
        else {
            return nil
        }
        return arguments[optionIndex + 1]
    }

    private static func printSelectionDiagnostic(
        bundleIdentifier: String?
    ) {
        let reader = AccessibilitySelectionReader()
        let result: AccessibilitySelectionReadResult
        if let bundleIdentifier,
            let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first
        {
            result = reader.readSelection(
                in: application.processIdentifier
            )
        } else if bundleIdentifier != nil {
            print(
                "trusted=\(AccessibilitySelectionReader.isTrusted)"
                    + " status=applicationNotRunning"
            )
            return
        } else {
            result = reader.readSelection()
        }

        switch result {
        case .selection(let selection):
            let range =
                selection.selectionRange.map {
                    "\($0.location):\($0.length)"
                } ?? "unavailable"
            print(
                "trusted=true status=selection"
                    + " app=\(selection.sourceApplicationName)"
                    + " length=\(selection.text.count)"
                    + " range=\(range)"
                    + " anchor=\(selection.anchorBounds)"
            )
        case .unavailable(let failure):
            print(
                "trusted=\(AccessibilitySelectionReader.isTrusted)"
                    + " status=\(failure.rawValue)"
            )
        }
    }
}
