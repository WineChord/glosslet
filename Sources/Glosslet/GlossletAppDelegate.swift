import AppKit
import Combine
import CoreServices
import GlossletCore

@MainActor
final class GlossletAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = AppPreferences()
    private let permissionMonitor: AccessibilityPermissionMonitor
    private lazy var conversation = ConversationController(
        preferences: preferences
    )
    private lazy var panels = PanelCoordinator(
        conversation: conversation,
        preferences: preferences,
        permissionMonitor: permissionMonitor
    )
    private lazy var selectionMonitor = SelectionMonitor {
        [weak self] selection in
        guard let self,
            self.preferences.selectionEnabled,
            self.permissionMonitor.isTrusted
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
    private var isPreviewSession = false

    override init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--render-onboarding-ready-preview") {
            permissionMonitor = AccessibilityPermissionMonitor {
                true
            }
        } else {
            permissionMonitor = AccessibilityPermissionMonitor()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let isRenderingPreview = arguments.contains("--render-preview")
        let isThinkingPreview = arguments.contains(
            "--render-thinking-preview"
        )
        let isToolbarPreview = arguments.contains(
            "--render-toolbar-preview"
        )
        let isOnboardingPreview =
            arguments.contains(
                "--render-onboarding-preview"
            ) || arguments.contains("--render-onboarding-ready-preview")
        isPreviewSession =
            isRenderingPreview || isThinkingPreview || isToolbarPreview
            || isOnboardingPreview
        configureStatusItem()
        bindPreferences()
        permissionMonitor.start()

        if isOnboardingPreview {
            panels.showOnboarding()
        } else if isToolbarPreview {
            NSApp.setActivationPolicy(.regular)
            let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
            let anchor = CGRect(
                x: visibleFrame.minX + min(300, visibleFrame.width / 2),
                y: visibleFrame.maxY - min(180, visibleFrame.height / 3),
                width: 1,
                height: 18
            )
            panels.showToolbar(
                for: SelectionSnapshot(
                    text: "Glosslet toolbar preview",
                    sourceApplicationName: "Glosslet Preview",
                    sourceBundleIdentifier: nil,
                    sourceProcessIdentifier:
                        ProcessInfo.processInfo.processIdentifier,
                    bounds: anchor,
                    anchorBounds: anchor
                )
            )
            NSApp.activate(ignoringOtherApps: true)
        } else if isRenderingPreview || isThinkingPreview {
            NSApp.setActivationPolicy(.regular)
            if isThinkingPreview {
                conversation.loadThinkingPreview()
            } else {
                conversation.loadRenderingPreview()
            }
            let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
            panels.showConversation(
                anchor: CGRect(
                    x: visibleFrame.midX,
                    y: visibleFrame.midY,
                    width: 1,
                    height: 1
                )
            )
            NSApp.activate(ignoringOtherApps: true)
        } else {
            selectionMonitor.start()
            conversation.prepare()
            if !preferences.completedOnboarding
                || !permissionMonitor.isTrusted
                || !isLoginItemLaunch
            {
                panels.showMainWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionMonitor.stop()
        permissionMonitor.stop()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows _: Bool
    ) -> Bool {
        guard !isPreviewSession else {
            return false
        }
        panels.showMainWindow()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        if let button = item.button {
            button.image = Self.menuBarImage()
            button.toolTip = "Glosslet"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildStatusMenu(menu)
        updateStatusItemTooltip()
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

        permissionMonitor.onChange = { [weak self] isTrusted in
            guard let self else {
                return
            }
            if isTrusted {
                self.selectionMonitor.probeNow()
            } else {
                self.panels.hideToolbar()
            }
            self.updateStatusItemTooltip()
        }
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let readinessItem = NSMenuItem(
            title: permissionMonitor.isTrusted
                ? L10n.readyStatus
                : L10n.permissionRequiredStatus,
            action: nil,
            keyEquivalent: ""
        )
        readinessItem.isEnabled = false
        readinessItem.image = NSImage(
            systemSymbolName:
                permissionMonitor.isTrusted
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill",
            accessibilityDescription: nil
        )
        menu.addItem(readinessItem)

        let openItem = NSMenuItem(
            title: L10n.openGlosslet,
            action: #selector(openGlosslet),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.image = NSImage(
            systemSymbolName: "macwindow",
            accessibilityDescription: nil
        )
        menu.addItem(openItem)
        menu.addItem(.separator())

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

        let conversationItem = NSMenuItem(
            title: L10n.showConversation,
            action: #selector(showConversation),
            keyEquivalent: ""
        )
        conversationItem.target = self
        conversationItem.image = NSImage(
            systemSymbolName: "bubble.left.and.text.bubble.right",
            accessibilityDescription: nil
        )
        conversationItem.isEnabled =
            conversation.selection != nil || conversation.threadID != nil
        menu.addItem(conversationItem)

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

        if !permissionMonitor.isTrusted {
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

    @objc private func openGlosslet() {
        panels.showMainWindow()
    }

    @objc private func openSettings() {
        panels.showSettings()
    }

    @objc private func showConversation() {
        panels.showExistingConversation()
    }

    @objc private func requestAccessibility() {
        AccessibilitySelectionReader.openAccessibilitySettings()
        panels.showOnboarding()
        permissionMonitor.refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private static func menuBarImage() -> NSImage {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in
            let path = NSBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.lineWidth = 1.65

            for y in [5.0, 9.0, 13.0] {
                path.move(to: NSPoint(x: 3.2, y: y))
                path.curve(
                    to: NSPoint(x: 13.4, y: 9),
                    controlPoint1: NSPoint(x: 9.2, y: y),
                    controlPoint2: NSPoint(x: 10.7, y: 9)
                )
            }
            NSColor.black.setStroke()
            path.stroke()

            let aperture = NSBezierPath()
            aperture.move(to: NSPoint(x: 13.4, y: 7.2))
            aperture.line(to: NSPoint(x: 15.2, y: 9))
            aperture.line(to: NSPoint(x: 13.4, y: 10.8))
            aperture.line(to: NSPoint(x: 11.6, y: 9))
            aperture.close()
            NSColor.black.setFill()
            aperture.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Glosslet"
        return image
    }

    private func updateStatusItemTooltip() {
        statusItem?.button?.toolTip =
            permissionMonitor.isTrusted
            ? L10n.readyStatus
            : L10n.permissionRequiredStatus
    }

    private var isLoginItemLaunch: Bool {
        NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
    }
}
