import AppKit
import GlossletCore

@MainActor
final class SelectionMonitor {
    typealias SelectionHandler = (SelectionSnapshot?) -> Void

    private let reader: AccessibilitySelectionReader
    private let handler: SelectionHandler
    private var globalMonitor: Any?
    private var applicationObserver: NSObjectProtocol?
    private var pollingTimer: Timer?
    private var pendingProbe: DispatchWorkItem?
    private var lastSelection: SelectionSnapshot?

    init(
        reader: AccessibilitySelectionReader =
            AccessibilitySelectionReader(),
        handler: @escaping SelectionHandler
    ) {
        self.reader = reader
        self.handler = handler
    }

    func start() {
        guard globalMonitor == nil else {
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .keyUp]
        ) { [weak self] event in
            Task { @MainActor in
                guard
                    event.type == .leftMouseUp
                        || Self.isSelectionKey(event)
                else {
                    return
                }
                let mouseLocation = NSEvent.mouseLocation
                if event.type == .leftMouseUp,
                    NSApp.windows.contains(where: {
                        $0.isVisible && $0.frame.contains(mouseLocation)
                    })
                {
                    return
                }
                self?.scheduleProbe(
                    anchorHint:
                        event.type == .leftMouseUp
                        ? mouseLocation
                        : nil
                )
            }
        }

        applicationObserver = NSWorkspace.shared.notificationCenter
            .addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    if let application = notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication,
                        application.processIdentifier
                            == ProcessInfo.processInfo.processIdentifier
                    {
                        return
                    }
                    self?.clear()
                }
            }

        let timer = Timer(timeInterval: 0.45, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.probe(clearWhenEmpty: false, anchorHint: nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    func stop() {
        pendingProbe?.cancel()
        pendingProbe = nil
        pollingTimer?.invalidate()
        pollingTimer = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = nil
        if let applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                applicationObserver
            )
        }
        applicationObserver = nil
        clear()
    }

    func probeNow() {
        probe(clearWhenEmpty: true, anchorHint: nil)
    }

    private func scheduleProbe(anchorHint: CGPoint?) {
        pendingProbe?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.probe(
                clearWhenEmpty: true,
                anchorHint: anchorHint
            )
        }
        pendingProbe = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(90),
            execute: work
        )
    }

    private func probe(
        clearWhenEmpty: Bool,
        anchorHint: CGPoint?
    ) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier
        {
            return
        }
        let selection = reader.currentSelection(anchorHint: anchorHint)
        guard let selection else {
            if clearWhenEmpty {
                clear()
            }
            return
        }
        let sameSelection =
            lastSelection?.representsSameSelection(as: selection) == true
        let anchorChanged =
            lastSelection?.anchorBounds.integral
            != selection.anchorBounds.integral
        guard !sameSelection || (anchorHint != nil && anchorChanged) else {
            return
        }
        lastSelection = selection
        handler(selection)
    }

    private func clear() {
        lastSelection = nil
        handler(nil)
    }

    private static func isSelectionKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.shift) {
            return true
        }
        return event.keyCode == 0x24
            || event.keyCode == 0x7B
            || event.keyCode == 0x7C
            || event.keyCode == 0x7D
            || event.keyCode == 0x7E
    }
}
