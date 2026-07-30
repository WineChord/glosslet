import AppKit
import GlossletCore
import SwiftUI

private enum GlossletPalette {
    static let panelBorder = Color.primary.opacity(0.1)
    static let subtleBorder = Color.primary.opacity(0.075)
    static let subtleFill = Color.primary.opacity(0.045)
    static let warning = Color(
        red: 0.82,
        green: 0.47,
        blue: 0.12
    )
}

struct GlossletMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct SelectionToolbarView: View {
    let onExplain: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            SelectionToolbarButton(
                title: L10n.explain,
                systemImage: "sparkles",
                action: onExplain
            )
            Divider()
                .frame(height: 16)
                .opacity(0.5)
            SelectionToolbarButton(
                title: L10n.copy,
                systemImage: "doc.on.doc",
                action: onCopy
            )
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.11))
        }
        .shadow(color: .black.opacity(0.13), radius: 18, y: 7)
    }
}

private struct SelectionToolbarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            isHovering ? GlossletPalette.subtleFill : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}

struct ConversationView: View {
    @ObservedObject var conversation: ConversationController
    @ObservedObject var presentation: ConversationPresentationState
    let onClose: () -> Void

    @State private var followUp = ""
    @State private var configurationMenu: ConfigurationMenu?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            content
            Divider().opacity(0.45)
            composer
        }
        .frame(minWidth: 430, idealWidth: 490, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(GlossletPalette.panelBorder)
        }
        .tint(.primary)
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                GlossletMark(size: 27)
                Text("Glosslet")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.1)
                if conversation.threadID != nil {
                    Circle()
                        .fill(Color.green.opacity(0.82))
                        .frame(width: 5, height: 5)
                        .help(L10n.taskSaved)
                        .accessibilityLabel(L10n.taskSaved)
                }

                Spacer(minLength: 10)

                HStack(spacing: 3) {
                    HeaderIconButton(
                        systemImage: "plus",
                        help: L10n.newTask,
                        isEnabled: conversation.selection != nil
                    ) {
                        conversation.startNewTaskForCurrentSelection()
                    }

                    HeaderIconButton(
                        systemImage: "arrow.up.right.square",
                        help: L10n.openCodex,
                        isEnabled: conversation.threadID != nil
                    ) {
                        conversation.openInCodex()
                    }

                    HeaderIconButton(
                        systemImage:
                            presentation.isPinned
                            ? "pin.fill"
                            : "pin",
                        help:
                            presentation.isPinned
                            ? L10n.unpinWindow
                            : L10n.pinWindow,
                        isActive: presentation.isPinned
                    ) {
                        presentation.togglePin()
                    }

                    HeaderIconButton(
                        systemImage: "xmark",
                        help: L10n.close,
                        action: onClose
                    )
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 50)

            HStack(spacing: 8) {
                ModelSelectionControl(
                    conversation: conversation,
                    isExpanded: configurationMenu == .model
                ) {
                    toggleConfigurationMenu(.model)
                }
                ReasoningSelectionControl(
                    conversation: conversation,
                    isExpanded: configurationMenu == .reasoning
                ) {
                    toggleConfigurationMenu(.reasoning)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 16)
            .padding(
                .bottom,
                configurationMenu == nil ? 10 : 8
            )

            if let configurationMenu {
                configurationDrawer(for: configurationMenu)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(
                        .move(edge: .top).combined(with: .opacity)
                    )
            }
        }
        .background(Color.primary.opacity(0.018))
        .animation(
            .easeOut(duration: 0.14),
            value: configurationMenu
        )
    }

    private var content: some View {
        VStack(spacing: 8) {
            MarkdownTranscriptView(
                selection: conversation.selection,
                messages: conversation.messages
            )

            if let approval = conversation.pendingApproval {
                ApprovalCard(
                    approval: approval,
                    onAllowOnce: {
                        conversation.resolveApproval(allow: true)
                    },
                    onAllowSession: {
                        conversation.resolveApproval(
                            allow: true,
                            forSession: true
                        )
                    },
                    onDeny: {
                        conversation.resolveApproval(allow: false)
                    }
                )
                .padding(.horizontal, 16)
            }

            if let error = conversation.errorMessage {
                ErrorCard(message: error)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.008))
    }

    private var composer: some View {
        VStack(spacing: 7) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    L10n.askFollowUp,
                    text: $followUp,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .focused($isComposerFocused)
                .onSubmit {
                    submit()
                }

                ComposerActionButton(
                    isBusy: conversation.isBusy,
                    isEnabled: canSubmit
                ) {
                    if conversation.isBusy {
                        conversation.stop()
                    } else {
                        submit()
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .frame(minHeight: 42)
            .background(GlossletPalette.subtleFill)
            .clipShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(GlossletPalette.subtleBorder)
            }

            HStack(spacing: 6) {
                if conversation.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Circle()
                        .fill(
                            conversation.errorMessage == nil
                                ? Color.green.opacity(0.8)
                                : GlossletPalette.warning
                        )
                        .frame(width: 5, height: 5)
                }

                Text(conversation.statusText)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                Text(L10n.returnHint)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            .font(.system(size: 9.75))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .background(Color.primary.opacity(0.018))
    }

    private var canSubmit: Bool {
        conversation.isBusy
            || !followUp.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    private func submit() {
        let text = followUp
        guard
            !text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            return
        }
        followUp = ""
        conversation.sendFollowUp(text)
    }

    private func toggleConfigurationMenu(_ menu: ConfigurationMenu) {
        configurationMenu = configurationMenu == menu ? nil : menu
    }

    @ViewBuilder
    private func configurationDrawer(
        for menu: ConfigurationMenu
    ) -> some View {
        switch menu {
        case .model:
            ModelSelectionDrawer(
                conversation: conversation,
                onDismiss: { configurationMenu = nil }
            )
        case .reasoning:
            ReasoningSelectionDrawer(
                conversation: conversation,
                onDismiss: { configurationMenu = nil }
            )
        }
    }
}

private enum ConfigurationMenu {
    case model
    case reasoning
}

private struct ModelSelectionControl: View {
    @ObservedObject var conversation: ConversationController
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SelectorPill(
                systemImage: "cpu",
                title: conversation.currentChoice.displayName,
                width: 180,
                isExpanded: isExpanded
            )
        }
        .buttonStyle(.plain)
        .disabled(conversation.isBusy)
        .help(L10n.chooseModel)
        .accessibilityLabel(
            "\(L10n.chooseModel): \(conversation.currentChoice.displayName)"
        )
    }
}

private struct ReasoningSelectionControl: View {
    @ObservedObject var conversation: ConversationController
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SelectorPill(
                systemImage: "slider.horizontal.3",
                title: reasoningTitle,
                width: 138,
                isExpanded: isExpanded
            )
        }
        .buttonStyle(.plain)
        .disabled(
            conversation.isBusy
                || conversation.reasoningOptions.isEmpty
        )
        .help(L10n.chooseReasoning)
        .accessibilityLabel(
            "\(L10n.chooseReasoning): \(reasoningTitle)"
        )
    }

    private var reasoningTitle: String {
        guard let effort = conversation.currentChoice.reasoningEffort else {
            return L10n.automatic
        }
        return "\(L10n.reasoning) · \(L10n.reasoningLabel(effort))"
    }
}

private struct ModelSelectionDrawer: View {
    @ObservedObject var conversation: ConversationController
    let onDismiss: () -> Void

    var body: some View {
        ConfigurationDrawer(title: L10n.chooseModel) {
            ConfigurationOptionButton(
                title: L10n.latestLowest,
                subtitle: conversation.visibleModels
                    .first(where: \.isDefault)?.displayName,
                isSelected:
                    conversation.activeModelPolicy == .latestLowest
            ) {
                conversation.selectLatestModelAndLowestEffort()
                onDismiss()
            }

            ConfigurationOptionButton(
                title: L10n.codexDefaults,
                subtitle: L10n.text(
                    "Use the model and effort from Codex configuration",
                    "使用 Codex 配置中的模型与推理强度"
                ),
                isSelected:
                    conversation.activeModelPolicy == .codexDefault
            ) {
                conversation.selectCodexDefaults()
                onDismiss()
            }

            if !conversation.visibleModels.isEmpty {
                Divider()
                    .padding(.vertical, 3)

                ForEach(conversation.visibleModels) { model in
                    ConfigurationOptionButton(
                        title: model.displayName,
                        subtitle: model.model,
                        isSelected:
                            conversation.activeModelPolicy == .custom
                            && conversation.currentChoice.model
                                == model.model
                    ) {
                        conversation.selectModel(model)
                        onDismiss()
                    }
                }
            }
        }
    }
}

private struct ReasoningSelectionDrawer: View {
    @ObservedObject var conversation: ConversationController
    let onDismiss: () -> Void

    var body: some View {
        ConfigurationDrawer(title: L10n.chooseReasoning) {
            ForEach(
                conversation.reasoningOptions,
                id: \.effort
            ) { option in
                ConfigurationOptionButton(
                    title: L10n.reasoningLabel(option.effort),
                    subtitle: L10n.reasoningDescription(
                        option.effort,
                        fallback: option.description
                    ),
                    isSelected:
                        conversation.currentChoice.reasoningEffort
                        == option.effort
                ) {
                    conversation.selectReasoningEffort(option.effort)
                    onDismiss()
                }
            }
        }
    }
}

private struct ConfigurationDrawer<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .frame(height: 32)

            Divider().opacity(0.5)

            ScrollView {
                VStack(spacing: 2) {
                    content
                }
                .padding(6)
            }
            .frame(maxHeight: 190)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GlossletPalette.panelBorder)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }
}

private struct ConfigurationOptionButton: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 14)
                    .opacity(isSelected ? 1 : 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 9.75))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .background(
                isHovering || isSelected
                    ? GlossletPalette.subtleFill
                    : Color.clear
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            [title, subtitle]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}

private struct SelectorPill: View {
    let systemImage: String
    let title: String
    let width: CGFloat
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 13)
            Text(title)
                .font(.system(size: 11.25, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            Image(
                systemName:
                    isExpanded ? "chevron.up" : "chevron.down"
            )
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: 30)
        .contentShape(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .background(GlossletPalette.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(GlossletPalette.subtleBorder)
        }
    }
}

private struct HeaderIconButton: View {
    let systemImage: String
    let help: String
    var isEnabled = true
    var isActive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 27, height: 27)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isActive
                ? Color(nsColor: .windowBackgroundColor)
                : Color.primary.opacity(isEnabled ? 0.82 : 0.3)
        )
        .background(
            isActive
                ? Color.primary
                : isHovering && isEnabled
                    ? GlossletPalette.subtleFill
                    : Color.clear
        )
        .clipShape(Circle())
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ComposerActionButton: View {
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isBusy ? "stop.fill" : "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(
                    Color(nsColor: .windowBackgroundColor)
                )
                .background(
                    Color.primary.opacity(isEnabled ? 0.94 : 0.2)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(isBusy ? L10n.stop : L10n.send)
        .accessibilityLabel(isBusy ? L10n.stop : L10n.send)
    }
}

private struct ApprovalCard: View {
    let approval: PendingApproval
    let onAllowOnce: () -> Void
    let onAllowSession: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(approval.title, systemImage: "hand.raised.fill")
                .font(.system(size: 11.5, weight: .semibold))
            Text(approval.detail)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(4)
                .textSelection(.enabled)
            HStack {
                Button(L10n.deny, action: onDeny)
                    .buttonStyle(.plain)
                Spacer()
                Button(L10n.allowSession, action: onAllowSession)
                Button(L10n.allowOnce, action: onAllowOnce)
                    .buttonStyle(.borderedProminent)
            }
            .font(.system(size: 11))
        }
        .padding(11)
        .background(GlossletPalette.warning.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(GlossletPalette.warning.opacity(0.2))
        }
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .lineLimit(4)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(GlossletPalette.warning)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlossletPalette.warning.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
