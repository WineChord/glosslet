import AppKit
import Combine
import os

@MainActor
final class AccessibilityPermissionMonitor: ObservableObject {
    typealias TrustProvider = () -> Bool

    @Published private(set) var isTrusted: Bool
    var onChange: ((Bool) -> Void)?

    private let trustProvider: TrustProvider
    private let logger = Logger(
        subsystem: "com.winechord.glosslet",
        category: "accessibility"
    )
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    init(
        trustProvider: @escaping TrustProvider = {
            AccessibilitySelectionReader.isTrusted
        }
    ) {
        self.trustProvider = trustProvider
        isTrusted = trustProvider()
    }

    func start() {
        guard timer == nil else {
            refresh()
            return
        }

        refresh()
        logger.notice("Accessibility trust at launch: \(self.isTrusted)")
        let timer = Timer(timeInterval: 0.5, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    func refresh() {
        let currentValue = trustProvider()
        guard currentValue != isTrusted else {
            return
        }
        isTrusted = currentValue
        logger.notice("Accessibility trust changed: \(currentValue)")
        onChange?(currentValue)
    }
}
