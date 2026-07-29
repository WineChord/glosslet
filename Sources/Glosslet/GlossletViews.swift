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
        HStack(spacing: 3) {
            SelectionToolbarButton(
                title: L10n.explain,
                systemImage: "sparkles",
                action: onExplain
            )
            Divider()
                .frame(height: 17)
                .opacity(0.6)
            SelectionToolbarButton(
                title: L10n.copy,
                systemImage: "doc.on.doc",
                action: onCopy
            )
        }
        .padding(5)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
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
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
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
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            content
            Divider().opacity(0.45)
            composer
        }
        .frame(minWidth: 410, idealWidth: 470, minHeight: 460)
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
        HStack(spacing: 10) {
            GlossletMark(size: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Glosslet")
                        .font(.system(size: 14, weight: .semibold))
                    if conversation.threadID != nil {
                        Circle()
                            .fill(Color.green.opacity(0.82))
                            .frame(width: 5, height: 5)
                            .accessibilityLabel(L10n.taskSaved)
                    }
                }

                Text(modelSummary)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.018))
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
                .padding(.horizontal, 12)
            }

            if let error = conversation.errorMessage {
                ErrorCard(message: error)
                    .padding(.horizontal, 12)
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
            .padding(.leading, 11)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
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

                Spacer()

                Text(L10n.returnHint)
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 9.75))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 11)
        .background(Color.primary.opacity(0.018))
    }

    private var modelSummary: String {
        var components = [conversation.currentChoice.displayName]
        if let effort = conversation.currentChoice.reasoningEffort {
            components.append(reasoningLabel(effort))
        }
        if conversation.threadID != nil {
            components.append(L10n.saved)
        }
        return components.joined(separator: "  ·  ")
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

    private func reasoningLabel(_ effort: String) -> String {
        switch effort {
        case "low":
            return L10n.text("Low", "低推理")
        case "minimal":
            return L10n.text("Minimal", "最小推理")
        case "none":
            return L10n.text("None", "无推理")
        default:
            return L10n.text(
                effort.capitalized,
                "\(effort) 推理"
            )
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
