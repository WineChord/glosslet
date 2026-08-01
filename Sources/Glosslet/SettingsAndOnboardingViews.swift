import AppKit
import GlossletCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var conversation: ConversationController
    @ObservedObject var permissionMonitor: AccessibilityPermissionMonitor
    @State private var launchError: String?
    @State private var launchRequiresApproval = false
    @State private var permissionRepairError: String?
    @State private var isRepairingPermission = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label(L10n.general, systemImage: "switch.2")
                }
            codexTab
                .tabItem {
                    Label(L10n.codex, systemImage: "sparkles")
                }
            aboutTab
                .tabItem {
                    Label(L10n.about, systemImage: "info.circle")
                }
        }
        .padding(18)
        .frame(width: 530, height: 410)
        .tint(Color(red: 0.17, green: 0.16, blue: 0.35))
        .task {
            permissionMonitor.refresh()
            refreshLaunchAtLogin()
            await conversation.refreshModels(showErrors: false)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshLaunchAtLogin()
        }
    }

    private var generalTab: some View {
        Form {
            Toggle(
                L10n.selectionToolbar,
                isOn: $preferences.selectionEnabled
            )
            Toggle(
                L10n.launchAtLogin,
                isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: updateLaunchAtLogin
                )
            )

            LabeledContent(L10n.accessibilityTitle) {
                if permissionMonitor.isTrusted {
                    Label(
                        L10n.accessGranted,
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                } else {
                    Button(L10n.grantAccess) {
                        AccessibilitySelectionReader
                            .openAccessibilitySettings()
                        permissionMonitor.refresh()
                    }
                }
            }

            if !permissionMonitor.isTrusted {
                Text(L10n.accessibilityRepairHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(L10n.repairAccess) {
                    repairAccessibilityPermission()
                }
                .disabled(isRepairingPermission)

                if let permissionRepairError {
                    Text(permissionRepairError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Picker(
                L10n.responseLanguage,
                selection: $preferences.explanationLanguage
            ) {
                Text(L10n.automatic)
                    .tag(ExplanationLanguage.automatic)
                Text(L10n.systemLanguage)
                    .tag(ExplanationLanguage.system)
                Text(L10n.simplifiedChinese)
                    .tag(ExplanationLanguage.simplifiedChinese)
                Text(L10n.english)
                    .tag(ExplanationLanguage.english)
            }

            if let launchError {
                Text(launchError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if launchRequiresApproval {
                Button(L10n.openLoginItemsSettings) {
                    LaunchAtLoginController.openSystemSettings()
                }
            }

            Text(L10n.privacyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
    }

    private var codexTab: some View {
        Form {
            Picker(
                L10n.conversationMode,
                selection: $preferences.threadMode
            ) {
                Text(L10n.reuseTask).tag(ThreadMode.reuseFixed)
                Text(L10n.newForEach).tag(ThreadMode.newPerExplanation)
            }

            Picker(
                L10n.modelMode,
                selection: $preferences.modelPolicy
            ) {
                Text(L10n.latestLowest).tag(ModelPolicy.latestLowest)
                Text(L10n.codexDefaults).tag(ModelPolicy.codexDefault)
                Text(L10n.custom).tag(ModelPolicy.custom)
            }

            if preferences.modelPolicy == .custom {
                Picker(
                    L10n.text("Custom model", "自定义模型"),
                    selection: Binding(
                        get: {
                            preferences.customModelID
                                ?? conversation.availableModels.first?.id
                                ?? ""
                        },
                        set: { preferences.customModelID = $0 }
                    )
                ) {
                    ForEach(
                        conversation.availableModels.filter {
                            !$0.hidden && $0.id != "codex-auto-review"
                        }
                    ) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }

                if let selectedModel {
                    Picker(
                        L10n.text("Reasoning", "推理程度"),
                        selection: Binding(
                            get: {
                                preferences.customEffort
                                    ?? selectedModel.defaultReasoningEffort
                            },
                            set: { preferences.customEffort = $0 }
                        )
                    ) {
                        ForEach(
                            selectedModel.supportedReasoningEfforts,
                            id: \.effort
                        ) { option in
                            Text(option.effort).tag(option.effort)
                        }
                    }
                }
            }

            LabeledContent(L10n.fixedTask) {
                if let identifier = preferences.fixedThreadID {
                    HStack {
                        Text(shortIdentifier(identifier))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Button(L10n.openCodex) {
                            if let url = URL(
                                string: "codex://threads/\(identifier)"
                            ) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } else {
                    Text(L10n.noTaskYet)
                        .foregroundStyle(.secondary)
                }
            }

            Button(L10n.resetTask, role: .destructive) {
                preferences.resetFixedThread()
            }
            .disabled(preferences.fixedThreadID == nil)

            Text(
                L10n.text(
                    "Every Glosslet task is persistent and appears in the Codex app. Glosslet never creates hidden or ephemeral conversations.",
                    "Glosslet 创建的每个任务都会持久保存并显示在 Codex App 中，不会创建隐藏或临时会话。"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 14) {
            GlossletMark(size: 64)
            Text("Glosslet")
                .font(.system(size: 24, weight: .bold))
            Text("Version \(GlossletConstants.appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.unofficial)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link(
                "github.com/WineChord/glosslet",
                destination: GlossletConstants.repositoryURL
            )
            Spacer()
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }

    private var selectedModel: CodexModel? {
        conversation.availableModels.first {
            $0.id == preferences.customModelID
                || $0.model == preferences.customModelID
        } ?? conversation.availableModels.first
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            preferences.launchAtLogin =
                LaunchAtLoginController.isEnabled
            launchRequiresApproval =
                LaunchAtLoginController.status == .requiresApproval
            launchError = nil
        } catch {
            preferences.launchAtLogin = LaunchAtLoginController.isEnabled
            launchRequiresApproval =
                LaunchAtLoginController.status == .requiresApproval
            launchError = error.localizedDescription
        }
    }

    private func refreshLaunchAtLogin() {
        do {
            let isEnabled = try LaunchAtLoginController.synchronize(
                preferredEnabled: preferences.launchAtLogin
            )
            if preferences.launchAtLogin != isEnabled {
                preferences.launchAtLogin = isEnabled
            }
            launchError = nil
        } catch {
            preferences.launchAtLogin = LaunchAtLoginController.isEnabled
            launchError = error.localizedDescription
        }
        launchRequiresApproval =
            LaunchAtLoginController.status == .requiresApproval
    }

    private func repairAccessibilityPermission() {
        isRepairingPermission = true
        defer { isRepairingPermission = false }
        do {
            try AccessibilitySelectionReader.repairTrust()
            permissionRepairError = nil
            permissionMonitor.refresh()
        } catch {
            permissionRepairError = error.localizedDescription
        }
    }

    private func shortIdentifier(_ identifier: String) -> String {
        guard identifier.count > 18 else {
            return identifier
        }
        return String(identifier.prefix(8))
            + "…"
            + String(identifier.suffix(8))
    }
}

struct OnboardingView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var permissionMonitor: AccessibilityPermissionMonitor
    let onFinish: () -> Void

    @State private var permissionRepairError: String?
    @State private var isRepairingPermission = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                GlossletMark(size: 72)
                Text(
                    permissionMonitor.isTrusted
                        ? L10n.readyTitle
                        : L10n.onboardingTitle
                )
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                Text(
                    L10n.text(
                        "Select text in almost any app. A tiny Explain · Copy toolbar appears beside it, and Codex answers in a floating conversation you can keep using.",
                        "在几乎任何应用中选中文字，旁边就会出现简洁的“解释 · 复制”工具条。Codex 会在悬浮对话中流式作答，你也可以直接继续追问。"
                    )
                )
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 38)
            .padding(.top, 36)
            .padding(.bottom, 26)

            VStack(alignment: .leading, spacing: 13) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.accessibilityTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.accessibilityBody)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(
                        systemName: permissionMonitor.isTrusted
                            ? "checkmark.shield.fill"
                            : "hand.raised.fill"
                    )
                    .font(.system(size: 24))
                    .foregroundStyle(
                        permissionMonitor.isTrusted ? .green : .indigo
                    )
                }

                if permissionMonitor.isTrusted {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(
                            L10n.accessGranted,
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                        Text(L10n.readyBody)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(L10n.grantAccess) {
                            AccessibilitySelectionReader
                                .openAccessibilitySettings()
                            permissionMonitor.refresh()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Text(L10n.accessibilityRepairHint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(L10n.repairAccess) {
                            repairAccessibilityPermission()
                        }
                        .disabled(isRepairingPermission)

                        if let permissionRepairError {
                            Text(permissionRepairError)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.orange)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                        }
                    }
                }
            }
            .padding(18)
            .background(.quaternary.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(.horizontal, 30)

            HStack {
                Text(
                    permissionMonitor.isTrusted
                        ? L10n.menuBarContinuation
                        : L10n.text(
                            "Uses your existing Codex sign-in and settings.",
                            "沿用你现有的 Codex 登录状态与设置。"
                        )
                )
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.finishSetup) {
                    preferences.completedOnboarding = true
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!permissionMonitor.isTrusted)
            }
            .padding(30)
        }
        .frame(width: 540, height: 520)
        .background(.regularMaterial)
        .task {
            permissionMonitor.refresh()
        }
    }

    private func repairAccessibilityPermission() {
        isRepairingPermission = true
        defer { isRepairingPermission = false }
        do {
            try AccessibilitySelectionReader.repairTrust()
            permissionRepairError = nil
            permissionMonitor.refresh()
        } catch {
            permissionRepairError = error.localizedDescription
        }
    }
}
