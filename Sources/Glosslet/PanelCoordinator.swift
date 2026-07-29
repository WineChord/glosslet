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
final class PanelCoordinator {
    private let conversation: ConversationController
    private let preferences: AppPreferences
    private var toolbarPanel: NonactivatingToolbarPanel?
    private var conversationPanel: ConversationPanel?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var currentSelection: SelectionSnapshot?

    init(
        conversation: ConversationController,
        preferences: AppPreferences
    ) {
        self.conversation = conversation
        self.preferences = preferences
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
        let panel = conversationPanel ?? makeConversationPanel()
        if !panel.isVisible {
            let visibleFrame =
                screen(
                    containing: anchor
                )?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let size = CGSize(width: 440, height: 590)
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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 590),
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
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 390, height: 430)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]
        panel.contentView = NSHostingView(
            rootView: ConversationView(conversation: conversation)
        )
        conversationPanel = panel
        return panel
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
