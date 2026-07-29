import AppKit
import GlossletCore
import SwiftUI

private enum GlossletPalette {
    static let accent = Color(
        red: 0.17,
        green: 0.16,
        blue: 0.35
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
        HStack(spacing: 4) {
            toolbarButton(
                title: L10n.explain,
                systemImage: "sparkles",
                action: onExplain
            )
            Divider()
                .frame(height: 18)
            toolbarButton(
                title: L10n.copy,
                systemImage: "doc.on.doc",
                action: onCopy
            )
        }
        .padding(5)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(title)
    }
}

struct ConversationView: View {
    @ObservedObject var conversation: ConversationController
    @State private var followUp = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.55)
            content
            Divider().opacity(0.55)
            composer
        }
        .frame(minWidth: 390, idealWidth: 440, minHeight: 430)
        .background(.regularMaterial)
        .tint(GlossletPalette.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            GlossletMark(size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Glosslet")
                        .font(.system(size: 15, weight: .bold))
                    if conversation.threadID != nil {
                        Label(L10n.taskSaved, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                HStack(spacing: 4) {
                    Text(conversation.currentChoice.displayName)
                    if let effort =
                        conversation.currentChoice.reasoningEffort
                    {
                        Text("·")
                        Text(reasoningLabel(effort))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                conversation.startNewTaskForCurrentSelection()
            } label: {
                Image(systemName: "plus.bubble")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(L10n.newTask)
            .disabled(conversation.selection == nil)

            Button {
                conversation.openInCodex()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(L10n.openCodex)
            .disabled(conversation.threadID == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let selection = conversation.selection {
                        SelectionPreviewCard(selection: selection)
                    }

                    ForEach(conversation.messages) { message in
                        MessageView(message: message)
                            .id(message.id)
                    }

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
                        .id(approval.id)
                    }

                    if let error = conversation.errorMessage {
                        ErrorCard(message: error)
                    }
                }
                .padding(16)
            }
            .onChange(of: conversation.messages) { _, messages in
                guard let last = messages.last else {
                    return
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    L10n.askFollowUp,
                    text: $followUp,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...5)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.quaternary.opacity(0.55))
                .clipShape(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .onSubmit {
                    submit()
                }

                if conversation.isBusy {
                    Button {
                        conversation.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .help(L10n.stop)
                } else {
                    Button {
                        submit()
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        followUp.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                    .help(L10n.send)
                }
            }

            HStack {
                if conversation.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(
                            conversation.errorMessage == nil
                                ? Color.green
                                : Color.orange
                        )
                }
                Text(conversation.statusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    L10n.text(
                        "Return to send · Shift-Return for a new line",
                        "回车发送 · Shift-回车换行"
                    )
                )
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.thinMaterial)
    }

    private func submit() {
        let text = followUp
        followUp = ""
        conversation.sendFollowUp(text)
    }

    private func reasoningLabel(_ effort: String) -> String {
        switch effort {
        case "low":
            return L10n.text("low reasoning", "低推理")
        case "minimal":
            return L10n.text("minimal reasoning", "最小推理")
        case "none":
            return L10n.text("no reasoning", "无推理")
        default:
            return L10n.text("\(effort) reasoning", "\(effort) 推理")
        }
    }
}

private struct SelectionPreviewCard: View {
    let selection: SelectionSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                "\(L10n.selectedFrom) \(selection.sourceApplicationName)",
                systemImage: "text.quote"
            )
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)

            Text(selection.preview)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .textSelection(.enabled)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlossletPalette.accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(GlossletPalette.accent.opacity(0.12))
        }
    }
}

private struct MessageView: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 42)
            }

            VStack(alignment: .leading, spacing: 7) {
                if message.text.isEmpty && message.isStreaming {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.thinking)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    MarkdownText(message.text)
                }
            }
            .padding(message.role == .user ? 10 : 0)
            .background(
                message.role == .user
                    ? GlossletPalette.accent.opacity(0.12)
                    : Color.clear
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .frame(
                maxWidth: .infinity,
                alignment: message.role == .user ? .trailing : .leading
            )

            if message.role == .assistant {
                Spacer(minLength: 8)
            }
        }
    }
}

private struct MarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(attributedText)
            .font(.system(size: 13))
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedText: AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(text)
    }
}

private struct ApprovalCard: View {
    let approval: PendingApproval
    let onAllowOnce: () -> Void
    let onAllowSession: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(approval.title, systemImage: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(approval.detail)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(5)
                .textSelection(.enabled)
            HStack {
                Button(L10n.deny, action: onDeny)
                Spacer()
                Button(L10n.allowSession, action: onAllowSession)
                Button(L10n.allowOnce, action: onAllowOnce)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22))
        }
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
