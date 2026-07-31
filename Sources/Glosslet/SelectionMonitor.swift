import AppKit
import GlossletCore
import os

@MainActor
final class SelectionMonitor {
    typealias SelectionHandler = (SelectionSnapshot?) -> Void

    private let reader: AccessibilitySelectionReader
    private let handler: SelectionHandler
    private var globalMonitor: Any?
    private var applicationObserver: NSObjectProtocol?
    private var pollingTimer: Timer?
    private var pendingProbe: DispatchWorkItem?
    private var anchorTracker = SelectionAnchorTracker()
    private let logger = Logger(
        subsystem: "com.winechord.glosslet",
        category: "selection"
    )
    private var lastDiagnosticState: String?

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
            let eventType = event.type
            let anchorHint =
                eventType == .leftMouseUp
                ? NSEvent.mouseLocation
                : nil
            Task { @MainActor in
                guard
                    eventType == .leftMouseUp
                        || Self.isSelectionKey(event)
                else {
                    return
                }
                if let anchorHint,
                    NSApp.windows.contains(where: {
                        $0.isVisible && $0.frame.contains(anchorHint)
                    })
                {
                    return
                }
                self?.scheduleProbe(anchorHint: anchorHint)
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
        let readResult = reader.readSelection(anchorHint: anchorHint)
        guard case .selection(let selection) = readResult else {
            if case .unavailable(let failure) = readResult {
                logFailureIfChanged(failure)
            }
            if clearWhenEmpty {
                clear()
            }
            return
        }
        logSelectionIfChanged(selection)
        let fallbackPoint = anchorHint ?? NSEvent.mouseLocation
        let fallbackAnchor = CGRect(
            x: fallbackPoint.x,
            y: fallbackPoint.y,
            width: 1,
            height: 1
        )
        guard
            let stableSelection = anchorTracker.observe(
                selection,
                fallbackAnchor: fallbackAnchor
            )
        else {
            return
        }
        handler(stableSelection)
    }

    private func clear() {
        anchorTracker.clear()
        handler(nil)
    }

    private func logFailureIfChanged(
        _ failure: AccessibilitySelectionReadFailure
    ) {
        let state = "unavailable:\(failure.rawValue)"
        guard state != lastDiagnosticState else {
            return
        }
        lastDiagnosticState = state
        logger.notice("Selection unavailable: \(failure.rawValue, privacy: .public)")
    }

    private func logSelectionIfChanged(_ selection: SelectionSnapshot) {
        let rangeDescription =
            selection.selectionRange.map {
                "\($0.location):\($0.length)"
            } ?? "unknown"
        let state = [
            "selection",
            String(selection.sourceProcessIdentifier),
            String(selection.sourceElementIdentifier ?? 0),
            rangeDescription,
            String(selection.text.count),
        ].joined(separator: ":")
        guard state != lastDiagnosticState else {
            return
        }
        lastDiagnosticState = state
        logger.notice(
            "Selection captured from \(selection.sourceApplicationName, privacy: .public), length \(selection.text.count), anchor \(String(describing: selection.anchorBounds), privacy: .public)"
        )
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
