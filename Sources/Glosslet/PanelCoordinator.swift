import AppKit
import GlossletCore
import SwiftUI

private final class NonactivatingToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ConversationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ConversationPresentationState: ObservableObject {
    @Published private(set) var isPinned = false
    var onPinChanged: ((Bool) -> Void)?

    func togglePin() {
        isPinned.toggle()
        onPinChanged?(isPinned)
    }
}

@MainActor
final class PanelCoordinator: NSObject, NSWindowDelegate {
    private let conversation: ConversationController
    private let preferences: AppPreferences
    private let presentation = ConversationPresentationState()
    private var toolbarPanel: NonactivatingToolbarPanel?
    private var conversationPanel: ConversationPanel?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var currentSelection: SelectionSnapshot?
    private var lastConversationAnchor: CGRect?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var applicationResignObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?

    init(
        conversation: ConversationController,
        preferences: AppPreferences
    ) {
        self.conversation = conversation
        self.preferences = preferences
        super.init()
        presentation.onPinChanged = { [weak self] _ in
            self?.updateConversationDismissalBehavior()
        }
    }

    deinit {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let applicationResignObserver {
            NotificationCenter.default.removeObserver(
                applicationResignObserver
            )
        }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                workspaceActivationObserver
            )
        }
    }

    func showToolbar(for selection: SelectionSnapshot) {
        currentSelection = selection
        let panel = toolbarPanel ?? makeToolbarPanel()
        let view = SelectionToolbarView(
            onExplain: { [weak self] in
                self?.explainCurrentSelection()
            },
            onCopy: { [weak self] in
                self?.copyCurrentSelection()
            }
        )
        panel.contentView = NSHostingView(rootView: view)

        let size =
            panel.contentView?.fittingSize
            ?? CGSize(width: 176, height: 44)
        let visibleFrame =
            screen(
                containing: selection.bounds
            )?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrame(
            PanelPlacement.toolbarFrame(
                anchor: selection.bounds,
                panelSize: size,
                visibleFrame: visibleFrame
            ),
            display: false
        )
        panel.orderFrontRegardless()
    }

    func hideToolbar() {
        toolbarPanel?.orderOut(nil)
        currentSelection = nil
    }

    func showConversation(anchor: CGRect) {
        lastConversationAnchor = anchor
        let panel = conversationPanel ?? makeConversationPanel()
        if !panel.isVisible {
            let visibleFrame =
                screen(
                    containing: anchor
                )?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let size = CGSize(width: 470, height: 640)
            panel.setFrame(
                PanelPlacement.conversationFrame(
                    anchor: anchor,
                    panelSize: size,
                    visibleFrame: visibleFrame
                ),
                display: false
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        updateConversationDismissalBehavior()
    }

    func showExistingConversation() {
        guard conversation.selection != nil || conversation.threadID != nil
        else {
            return
        }
        if let lastConversationAnchor {
            showConversation(anchor: lastConversationAnchor)
            return
        }
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        showConversation(
            anchor: CGRect(
                x: visibleFrame.midX,
                y: visibleFrame.midY,
                width: 1,
                height: 1
            )
        )
    }

    func hideConversation() {
        conversationPanel?.orderOut(nil)
        stopOutsideClickMonitoring()
    }

    func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        let window = onboardingWindow ?? makeOnboardingWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === conversationPanel else {
            return
        }
        stopOutsideClickMonitoring()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === conversationPanel,
            !presentation.isPinned
        else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                self.conversationPanel?.isKeyWindow == false,
                !self.presentation.isPinned
            else {
                return
            }
            self.hideConversation()
        }
    }

    private func explainCurrentSelection() {
        guard let selection = currentSelection else {
            return
        }
        toolbarPanel?.orderOut(nil)
        conversation.explain(selection)
        showConversation(anchor: selection.bounds)
        currentSelection = nil
    }

    private func copyCurrentSelection() {
        guard let text = currentSelection?.text else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        hideToolbar()
    }

    private func makeToolbarPanel() -> NonactivatingToolbarPanel {
        let panel = NonactivatingToolbarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 176, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
        ]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        toolbarPanel = panel
        return panel
    }

    private func makeConversationPanel() -> ConversationPanel {
        let panel = ConversationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 640),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.title = "Glosslet"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 410, height: 460)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: ConversationView(
                conversation: conversation,
                presentation: presentation,
                onClose: { [weak self] in
                    self?.hideConversation()
                }
            )
        )
        conversationPanel = panel
        return panel
    }

    private func updateConversationDismissalBehavior() {
        guard let panel = conversationPanel else {
            return
        }
        panel.hidesOnDeactivate = !presentation.isPinned

        if presentation.isPinned {
            stopOutsideClickMonitoring()
            if panel.isVisible {
                panel.orderFrontRegardless()
            }
        } else if panel.isVisible {
            startOutsideClickMonitoring()
        }
    }

    private func startOutsideClickMonitoring() {
        guard globalMouseMonitor == nil,
            localMouseMonitor == nil,
            applicationResignObserver == nil,
            workspaceActivationObserver == nil,
            presentation.isPinned == false
        else {
            return
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissConversationWhenUnpinned()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self,
                    let panel = self.conversationPanel,
                    panel.isVisible,
                    !self.presentation.isPinned,
                    !panel.frame.contains(NSEvent.mouseLocation)
                else {
                    return
                }
                self.hideConversation()
            }
            return event
        }

        applicationResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissConversationWhenUnpinned()
            }
        }

        workspaceActivationObserver =
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let application = notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication,
                    application.processIdentifier
                        != ProcessInfo.processInfo.processIdentifier
                else {
                    return
                }
                Task { @MainActor in
                    self?.dismissConversationWhenUnpinned()
                }
            }
    }

    private func stopOutsideClickMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let applicationResignObserver {
            NotificationCenter.default.removeObserver(
                applicationResignObserver
            )
            self.applicationResignObserver = nil
        }
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                workspaceActivationObserver
            )
            self.workspaceActivationObserver = nil
        }
    }

    private func dismissConversationWhenUnpinned() {
        guard !presentation.isPinned else {
            return
        }
        hideConversation()
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 530, height: 410),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settings.replacingOccurrences(of: "…", with: "")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SettingsView(
                preferences: preferences,
                conversation: conversation
            )
        )
        settingsWindow = window
        return window
    }

    private func makeOnboardingWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Glosslet"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                preferences: preferences,
                onFinish: { [weak window] in
                    window?.close()
                }
            )
        )
        onboardingWindow = window
        return window
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
            ?? NSScreen.main
    }
}
