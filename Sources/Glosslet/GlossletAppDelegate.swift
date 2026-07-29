import AppKit
import Combine
import GlossletCore

@MainActor
final class GlossletAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = AppPreferences()
    private lazy var conversation = ConversationController(
        preferences: preferences
    )
    private lazy var panels = PanelCoordinator(
        conversation: conversation,
        preferences: preferences
    )
    private lazy var selectionMonitor = SelectionMonitor {
        [weak self] selection in
        guard let self,
            self.preferences.selectionEnabled,
            AccessibilitySelectionReader.isTrusted
        else {
            self?.panels.hideToolbar()
            return
        }
        if let selection {
            self.panels.showToolbar(for: selection)
        } else {
            self.panels.hideToolbar()
        }
    }

    private var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        bindPreferences()
        selectionMonitor.start()
        conversation.prepare()

        if !preferences.completedOnboarding
            || !AccessibilitySelectionReader.isTrusted
        {
            panels.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionMonitor.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "text.magnifyingglass",
                accessibilityDescription: "Glosslet"
            )
            button.image?.isTemplate = true
            button.toolTip = "Glosslet"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildStatusMenu(menu)
    }

    private func bindPreferences() {
        preferences.$selectionEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if !enabled {
                    self?.panels.hideToolbar()
                }
            }
            .store(in: &subscriptions)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let stateItem = NSMenuItem(
            title: preferences.selectionEnabled ? L10n.pause : L10n.resume,
            action: #selector(toggleSelection),
            keyEquivalent: ""
        )
        stateItem.target = self
        stateItem.image = NSImage(
            systemSymbolName:
                preferences.selectionEnabled ? "pause.circle" : "play.circle",
            accessibilityDescription: nil
        )
        menu.addItem(stateItem)

        let settingsItem = NSMenuItem(
            title: L10n.settings,
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: nil
        )
        menu.addItem(settingsItem)

        if !AccessibilitySelectionReader.isTrusted {
            let permissionItem = NSMenuItem(
                title: L10n.grantAccess,
                action: #selector(requestAccessibility),
                keyEquivalent: ""
            )
            permissionItem.target = self
            permissionItem.image = NSImage(
                systemSymbolName: "hand.raised",
                accessibilityDescription: nil
            )
            menu.addItem(permissionItem)
        }

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: L10n.quit,
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleSelection() {
        preferences.selectionEnabled.toggle()
        if preferences.selectionEnabled {
            selectionMonitor.probeNow()
        }
    }

    @objc private func openSettings() {
        panels.showSettings()
    }

    @objc private func requestAccessibility() {
        AccessibilitySelectionReader.requestTrustPrompt()
        panels.showOnboarding()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
