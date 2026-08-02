import AppKit
import Combine
import Foundation
import GlossletCore
import OSLog

private enum CodexRecoveryTrigger: String {
    case launch
    case selection
    case processTerminated = "process_terminated"
    case systemWake = "system_wake"
    case codexAvailable = "codex_available"
}

private struct CodexRequestLatencyTrace {
    let identifier = UUID().uuidString
    let kind: String
    let startedAt = Date()
    var didRecordFirstContent = false
    var inputTokens: Int?
    var cachedInputTokens: Int?
}

enum ConversationRole: Equatable {
    case user
    case assistant
}

struct ConversationMessage: Identifiable, Equatable {
    let id: UUID
    let role: ConversationRole
    var text: String
    var isStreaming: Bool
    var activityText: String?
    let startedAt: Date?

    init(
        id: UUID = UUID(),
        role: ConversationRole,
        text: String,
        isStreaming: Bool = false,
        activityText: String? = nil,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.activityText = activityText
        self.startedAt = startedAt
    }
}

struct PendingApproval: Identifiable, Equatable {
    let id: UUID
    let request: AppServerRequest
    let title: String
    let detail: String

    init(request: AppServerRequest, title: String, detail: String) {
        id = UUID()
        self.request = request
        self.title = title
        self.detail = detail
    }
}

@MainActor
final class ConversationController: ObservableObject {
    @Published private(set) var selection: SelectionSnapshot?
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var availableModels: [CodexModel] = []
    @Published private(set) var currentChoice = ModelChoice(
        model: nil,
        displayName: "Codex",
        reasoningEffort: nil
    )
    @Published private(set) var threadID: String?
    @Published private(set) var activeTurnID: String?
    @Published private(set) var statusText = L10n.connecting
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var pendingApproval: PendingApproval?

    private let client: CodexAppServerClient
    private let preferences: AppPreferences
    private var eventTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryGeneration = 0
    private var operationTask: Task<Void, Never>?
    private var deltaFlushTask: Task<Void, Never>?
    private var attachmentTask: Task<String, Error>?
    private var attachingThreadID: String?
    private var activeAssistantMessageID: UUID?
    private var pendingAssistantDelta = ""
    private var streamedItemIDs = Set<String>()
    private var requestStartedAt: Date?
    private var requestAwaitsCodexPreparation = false
    private var latencyTrace: CodexRequestLatencyTrace?
    private var threadAttachment = ThreadAttachmentState()
    private var attachedConnectionGeneration: Int?
    private var lastRuntimePrewarmAt: Date?
    private var lastSelectionProbeAt = Date.distantPast
    private var threadPreparationExpectedUntil: Date?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var catalogLoaded = false
    private var preferenceSubscriptions = Set<AnyCancellable>()
    private let lifecycleLogger = Logger(
        subsystem: "com.winechord.glosslet",
        category: "CodexLifecycle"
    )
    private let latencyLogger = Logger(
        subsystem: "com.winechord.glosslet",
        category: "CodexLatency"
    )

    init(
        client: CodexAppServerClient = CodexAppServerClient(),
        preferences: AppPreferences
    ) {
        self.client = client
        self.preferences = preferences
        eventTask = Task { [weak self, client] in
            let stream = await client.eventStream()
            for await event in stream {
                guard !Task.isCancelled else {
                    break
                }
                self?.handle(event)
            }
        }
        Publishers.CombineLatest3(
            preferences.$modelPolicy.removeDuplicates(),
            preferences.$customModelID.removeDuplicates(),
            preferences.$customEffort.removeDuplicates()
        )
        .dropFirst()
        .sink { [weak self] _ in
            self?.resolveCurrentChoice()
        }
        .store(in: &preferenceSubscriptions)

        let workspaceNotificationCenter =
            NSWorkspace.shared.notificationCenter
        for notificationName in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
        ] {
            let observer = workspaceNotificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard
                    let application = notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication,
                    application.bundleIdentifier == "com.openai.codex"
                else {
                    return
                }
                Task { @MainActor in
                    self?.codexBecameAvailable()
                }
            }
            workspaceObservers.append(observer)
        }
        workspaceObservers.append(
            workspaceNotificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRecovery(
                        trigger: .systemWake,
                        waitForPreferredControlSocket: true
                    )
                }
            }
        )
    }

    deinit {
        eventTask?.cancel()
        recoveryTask?.cancel()
        operationTask?.cancel()
        deltaFlushTask?.cancel()
        attachmentTask?.cancel()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func prepare() {
        scheduleRecovery(trigger: .launch, refreshModels: true)
    }

    func selectionDidBecomeAvailable() {
        guard !isBusy,
            Date().timeIntervalSince(lastSelectionProbeAt) >= 15
        else {
            return
        }
        lastSelectionProbeAt = Date()
        scheduleRecovery(trigger: .selection)
    }

    func loadRenderingPreview() {
        availableModels = [
            CodexModel(
                id: "gpt-5.6-sol",
                model: "gpt-5.6-sol",
                displayName: "GPT-5.6-Sol",
                description: "Glosslet rendering preview",
                hidden: false,
                isDefault: true,
                defaultReasoningEffort: "medium",
                supportedReasoningEfforts: [
                    ReasoningEffortOption(
                        effort: "low",
                        description: "Fast responses"
                    ),
                    ReasoningEffortOption(
                        effort: "medium",
                        description: "Balanced reasoning"
                    ),
                    ReasoningEffortOption(
                        effort: "high",
                        description: "Deeper reasoning"
                    ),
                ],
                serviceTiers: [
                    CodexServiceTier(
                        id: "priority",
                        name: "Fast",
                        description: "Priority processing"
                    )
                ]
            )
        ]
        catalogLoaded = true
        selection = SelectionSnapshot(
            text: "A deterministic preview of Glosslet's transcript renderer.",
            sourceApplicationName: "Glosslet Preview",
            sourceBundleIdentifier: nil,
            sourceProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            bounds: .zero
        )
        currentChoice = ModelChoice(
            model: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            reasoningEffort: "low",
            serviceTier: "priority"
        )
        threadID = nil
        activeTurnID = nil
        isBusy = false
        errorMessage = nil
        pendingApproval = nil
        statusText = L10n.done
        messages = [
            ConversationMessage(
                role: .assistant,
                text: """
                    ## Why this matters

                    Glosslet renders **CommonMark**, tables, task lists, links, \
                    quotations, highlighted code, and local LaTeX without a \
                    network renderer.

                    Euler's identity is \\(e^{i\\pi} + 1 = 0\\). A display \
                    equation stays readable when the panel narrows:

                    \\[
                    \\operatorname{softmax}(x_i)
                    = \\frac{e^{x_i}}{\\sum_{j=1}^{n} e^{x_j}}
                    \\]

                    | Surface | Behavior |
                    | --- | --- |
                    | Markdown | Incremental, selectable rendering |
                    | LaTeX | KaTeX with local fonts |
                    | Code | Highlighting and one-click copy |

                    ```swift
                    struct Selection {
                        let text: String
                        let source: String
                    }
                    ```

                    > Wide tables, equations, and code scroll inside their own
                    > content area instead of stretching the panel.

                    - [x] Persistent Codex task
                    - [x] Streaming transcript
                    - [ ] Your next follow-up
                    """
            ),
            ConversationMessage(
                role: .user,
                text: "Can I keep this window visible while I work elsewhere?"
            ),
            ConversationMessage(
                role: .assistant,
                text: """
                    Yes. Choose the **pin** in the header. By default the panel \
                    is unpinned and disappears as soon as focus moves outside \
                    Glosslet.
                    """
            ),
        ]
    }

    func loadThinkingPreview() {
        loadRenderingPreview()
        let startedAt = Date().addingTimeInterval(-12)
        requestStartedAt = startedAt
        isBusy = true
        statusText = L10n.thinking
        messages = [
            ConversationMessage(
                role: .assistant,
                text: "",
                isStreaming: true,
                activityText: L10n.thinking,
                startedAt: startedAt
            )
        ]
    }

    func explain(_ selection: SelectionSnapshot, forceNewTask: Bool = false) {
        cancelRecoveryForForegroundRequest()
        operationTask?.cancel()
        self.selection = selection
        messages = []
        errorMessage = nil
        pendingApproval = nil
        streamedItemIDs.removeAll()
        discardPendingDelta()
        activeAssistantMessageID = nil
        isBusy = true
        statusText = L10n.connecting
        requestStartedAt = Date()
        beginLatencyTrace(kind: "explanation")
        appendStreamingAssistant(activityText: L10n.connecting)

        operationTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try SelectionValidator.validate(selection)
                try ensureWorkspaceExists()
                if !catalogLoaded {
                    await refreshModels(showErrors: false)
                }
                resolveCurrentChoice()
                recordLatencyPhase("catalog_ready")

                let shouldCreate =
                    forceNewTask
                    || preferences.threadMode == .newPerExplanation
                var attachmentAction: ThreadAttachmentAction?
                if !shouldCreate,
                    let storedThreadID = preferences.fixedThreadID
                {
                    let action = await validatedAttachmentAction(
                        for: storedThreadID
                    )
                    attachmentAction = action
                    if action != .reuse {
                        updateAssistantActivity(L10n.restoringTask)
                    }
                }
                requestAwaitsCodexPreparation =
                    attachmentAction != nil && attachmentAction != .reuse
                    || threadPreparationExpectedUntil.map {
                        $0 > Date()
                    } == true
                let identifier = try await obtainThread(
                    forceNew: shouldCreate,
                    selection: selection
                )
                threadID = identifier
                recordLatencyPhase("thread_ready")
                updateAssistantActivity(
                    requestAwaitsCodexPreparation
                        ? L10n.preparingCodex
                        : L10n.thinking
                )

                let prompt = GlossletPromptBuilder.initialPrompt(
                    for: selection,
                    language: preferences.explanationLanguage,
                    systemLanguageIdentifier: Locale.current.identifier
                )
                recordLatencyPhase("turn_start_sent")
                let turnID = try await client.startTurn(
                    threadID: identifier,
                    text: prompt,
                    model: currentChoice.model,
                    reasoningEffort: currentChoice.reasoningEffort,
                    serviceTier: currentChoice.serviceTier,
                    workingDirectory:
                        GlossletConstants.defaultWorkspaceURL
                )
                activeTurnID = turnID
                recordLatencyPhase("turn_accepted")
            } catch is CancellationError {
                finishStreamingMessage()
                isBusy = false
                statusText = L10n.stopped
                requestStartedAt = nil
                finishLatencyTrace(outcome: "cancelled")
            } catch {
                fail(error)
            }
        }
    }

    func sendFollowUp(_ text: String) {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty, !isBusy else {
            return
        }

        cancelRecoveryForForegroundRequest()
        operationTask?.cancel()
        errorMessage = nil
        messages.append(
            ConversationMessage(role: .user, text: trimmed)
        )
        requestStartedAt = Date()
        beginLatencyTrace(kind: "follow_up")
        appendStreamingAssistant(activityText: L10n.preparingTask)
        isBusy = true
        statusText = L10n.preparingTask

        operationTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try ensureWorkspaceExists()
                let identifier: String
                if let threadID {
                    let action = await validatedAttachmentAction(
                        for: threadID
                    )
                    requestAwaitsCodexPreparation =
                        action != .reuse
                        || threadPreparationExpectedUntil.map {
                            $0 > Date()
                        } == true
                    if action != .reuse {
                        updateAssistantActivity(L10n.restoringTask)
                    }
                    identifier = try await attachThread(id: threadID)
                } else if let selection {
                    identifier = try await obtainThread(
                        forceNew: false,
                        selection: selection
                    )
                    threadID = identifier
                } else {
                    throw AppServerProtocolError.invalidResponse(
                        L10n.text(
                            "No Codex task is open.",
                            "当前没有打开的 Codex 任务。"
                        )
                    )
                }

                recordLatencyPhase("thread_ready")
                updateAssistantActivity(
                    requestAwaitsCodexPreparation
                        ? L10n.preparingCodex
                        : L10n.thinking
                )
                recordLatencyPhase("turn_start_sent")
                let turnID = try await client.startTurn(
                    threadID: identifier,
                    text: trimmed,
                    model: currentChoice.model,
                    reasoningEffort: currentChoice.reasoningEffort,
                    serviceTier: currentChoice.serviceTier,
                    workingDirectory:
                        GlossletConstants.defaultWorkspaceURL
                )
                activeTurnID = turnID
                recordLatencyPhase("turn_accepted")
            } catch is CancellationError {
                finishStreamingMessage()
                isBusy = false
                statusText = L10n.stopped
                requestStartedAt = nil
                finishLatencyTrace(outcome: "cancelled")
            } catch {
                fail(error)
            }
        }
    }

    func startNewTaskForCurrentSelection() {
        guard let selection else {
            return
        }
        explain(selection, forceNewTask: true)
    }

    func stop() {
        guard let threadID, let activeTurnID else {
            operationTask?.cancel()
            finishStreamingMessage()
            isBusy = false
            statusText = L10n.stopped
            requestStartedAt = nil
            finishLatencyTrace(outcome: "cancelled")
            return
        }
        Task { [weak self, client] in
            do {
                try await client.interruptTurn(
                    threadID: threadID,
                    turnID: activeTurnID
                )
            } catch {
                self?.fail(error)
            }
        }
    }

    func openInCodex() {
        guard let threadID,
            let url = URL(string: "codex://threads/\(threadID)")
        else {
            if let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex"
            ) {
                NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: .init()
                )
            }
            return
        }
        threadAttachment.markExternalHistoryMayHaveChanged()
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func refreshModels(showErrors: Bool = true) async -> Bool {
        do {
            availableModels = try await client.listModels()
            catalogLoaded = true
            resolveCurrentChoice()
            return true
        } catch {
            catalogLoaded = false
            if showErrors {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func codexBecameAvailable() {
        threadAttachment.markExternalHistoryMayHaveChanged()
        scheduleRecovery(
            trigger: .codexAvailable,
            waitForPreferredControlSocket: true
        )
    }

    private func cancelRecoveryForForegroundRequest() {
        recoveryGeneration += 1
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    private func scheduleRecovery(
        trigger: CodexRecoveryTrigger,
        refreshModels: Bool = false,
        waitForPreferredControlSocket: Bool = false
    ) {
        guard !isBusy else {
            return
        }
        if trigger == .selection, recoveryTask != nil {
            return
        }

        recoveryGeneration += 1
        let generation = recoveryGeneration
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            guard let self else {
                return
            }
            await performRecovery(
                trigger: trigger,
                refreshModels: refreshModels,
                waitForPreferredControlSocket:
                    waitForPreferredControlSocket
            )
            guard recoveryGeneration == generation else {
                return
            }
            recoveryTask = nil
        }
    }

    private func performRecovery(
        trigger: CodexRecoveryTrigger,
        refreshModels shouldRefreshModels: Bool,
        waitForPreferredControlSocket: Bool
    ) async {
        let startedAt = Date()
        lifecycleLogger.info(
            "recovery_started trigger=\(trigger.rawValue, privacy: .public)"
        )
        var backoff = RecoveryBackoff()

        while !Task.isCancelled {
            do {
                try ensureWorkspaceExists()
                let status = await client.connectionStatus()
                let storedFixedThreadID =
                    preferences.threadMode == .reuseFixed
                    ? preferences.fixedThreadID
                    : nil
                let attachmentIsReady =
                    storedFixedThreadID.map {
                        threadAttachment.action(for: $0) == .reuse
                            && status.generation
                                == attachedConnectionGeneration
                    } ?? true

                if trigger == .selection,
                    status.isReady,
                    attachmentIsReady,
                    let lastRuntimePrewarmAt,
                    Date().timeIntervalSince(lastRuntimePrewarmAt) < 120
                {
                    return
                }

                if waitForPreferredControlSocket,
                    !status.isReady,
                    status.lastTransport == .controlSocket,
                    !status.preferredControlSocketAvailable,
                    backoff.retryCount < 4
                {
                    throw AppServerProtocolError.processUnavailable
                }

                if !status.isReady
                    || storedFixedThreadID != nil
                        && status.generation
                            != attachedConnectionGeneration
                {
                    threadAttachment.markProcessTerminated()
                    attachedConnectionGeneration = nil
                }

                if shouldRefreshModels || !catalogLoaded {
                    let modelsReady = await refreshModels(
                        showErrors: false
                    )
                    guard modelsReady else {
                        throw AppServerProtocolError.processUnavailable
                    }
                }
                resolveCurrentChoice()

                var prewarmThreadID: String?
                if preferences.threadMode == .reuseFixed,
                    let storedThreadID = preferences.fixedThreadID
                {
                    do {
                        let action = await validatedAttachmentAction(
                            for: storedThreadID
                        )
                        let identifier = try await attachThread(
                            id: storedThreadID
                        )
                        guard !Task.isCancelled else {
                            return
                        }
                        threadID = identifier
                        prewarmThreadID = identifier
                        if action != .reuse {
                            threadPreparationExpectedUntil = Date()
                                .addingTimeInterval(20)
                        }
                    } catch let error as AppServerProtocolError {
                        guard Self.isMissingThread(error) else {
                            throw error
                        }
                        preferences.resetFixedThread()
                        threadID = nil
                        threadAttachment.markProcessTerminated()
                        attachedConnectionGeneration = nil
                    }
                }

                let runtimeReady = await client.prewarmRuntime(
                    workingDirectory:
                        GlossletConstants.defaultWorkspaceURL,
                    threadID: prewarmThreadID
                )
                guard runtimeReady else {
                    throw AppServerProtocolError.processUnavailable
                }

                let finalStatus = await client.connectionStatus()
                if prewarmThreadID != nil,
                    finalStatus.generation
                        != attachedConnectionGeneration
                {
                    threadAttachment.markProcessTerminated()
                    attachedConnectionGeneration = nil
                    throw AppServerProtocolError.processUnavailable
                }

                lastRuntimePrewarmAt = Date()
                let elapsedMilliseconds = Self.milliseconds(
                    since: startedAt
                )
                lifecycleLogger.info(
                    "recovery_ready trigger=\(trigger.rawValue, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public) attempts=\(backoff.retryCount + 1, privacy: .public)"
                )
                return
            } catch is CancellationError {
                return
            } catch {
                if let protocolError = error as? AppServerProtocolError,
                    !Self.isRetryableRecoveryError(protocolError)
                {
                    let elapsedMilliseconds = Self.milliseconds(
                        since: startedAt
                    )
                    lifecycleLogger.error(
                        "recovery_stopped trigger=\(trigger.rawValue, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public) attempts=\(backoff.retryCount + 1, privacy: .public)"
                    )
                    return
                }
                guard backoff.retryCount < backoff.delays.count else {
                    let elapsedMilliseconds = Self.milliseconds(
                        since: startedAt
                    )
                    lifecycleLogger.error(
                        "recovery_exhausted trigger=\(trigger.rawValue, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public) attempts=\(backoff.retryCount + 1, privacy: .public)"
                    )
                    return
                }
                let retryDelay = backoff.nextDelay()
                lifecycleLogger.notice(
                    "recovery_retry trigger=\(trigger.rawValue, privacy: .public) retry=\(backoff.retryCount, privacy: .public) delay_ms=\(Int(retryDelay * 1_000), privacy: .public)"
                )
                do {
                    try await Task.sleep(for: .seconds(retryDelay))
                } catch {
                    return
                }
            }
        }
    }

    var visibleModels: [CodexModel] {
        availableModels.filter {
            !$0.hidden && $0.id != "codex-auto-review"
        }
    }

    var activeModelPolicy: ModelPolicy {
        preferences.modelPolicy
    }

    var usesPriorityService: Bool {
        currentChoice.serviceTier == "priority"
    }

    var selectedModel: CodexModel? {
        if let modelID = currentChoice.model,
            let selected = visibleModels.first(where: {
                $0.id == modelID || $0.model == modelID
            })
        {
            return selected
        }
        return visibleModels.first(where: \.isDefault) ?? visibleModels.first
    }

    var reasoningOptions: [ReasoningEffortOption] {
        selectedModel?.supportedReasoningEfforts ?? []
    }

    func selectLatestModelAndLowestEffort() {
        guard !isBusy else {
            return
        }
        preferences.modelPolicy = .latestLowest
        resolveCurrentChoice()
    }

    func selectCodexDefaults() {
        guard !isBusy else {
            return
        }
        preferences.modelPolicy = .codexDefault
        resolveCurrentChoice()
    }

    func selectModel(_ model: CodexModel) {
        guard !isBusy else {
            return
        }
        let supported = Set(
            model.supportedReasoningEfforts.map(\.effort)
        )
        let effort =
            currentChoice.reasoningEffort.flatMap {
                supported.contains($0) ? $0 : nil
            }
            ?? ModelSelection.lowestEffort(
                in: model.supportedReasoningEfforts
            )
            ?? model.defaultReasoningEffort

        preferences.customModelID = model.id
        preferences.customEffort = effort
        preferences.modelPolicy = .custom
        resolveCurrentChoice()
    }

    func selectReasoningEffort(_ effort: String) {
        guard !isBusy,
            let model = selectedModel,
            model.supportedReasoningEfforts.contains(where: {
                $0.effort == effort
            })
        else {
            return
        }
        preferences.customModelID = model.id
        preferences.customEffort = effort
        preferences.modelPolicy = .custom
        resolveCurrentChoice()
    }

    func resolveApproval(allow: Bool, forSession: Bool = false) {
        guard let pendingApproval else {
            return
        }
        self.pendingApproval = nil

        Task { [weak self, client] in
            do {
                let result = Self.approvalResult(
                    for: pendingApproval.request,
                    allow: allow,
                    forSession: forSession
                )
                try await client.respond(
                    to: pendingApproval.request,
                    result: result
                )
            } catch {
                self?.fail(error)
            }
        }
    }

    private func ensureWorkspaceExists() throws {
        try FileManager.default.createDirectory(
            at: GlossletConstants.defaultWorkspaceURL,
            withIntermediateDirectories: true
        )
    }

    private func resolveCurrentChoice() {
        currentChoice = ModelSelection.resolve(
            policy: preferences.modelPolicy,
            models: availableModels,
            customModelID: preferences.customModelID,
            customEffort: preferences.customEffort
        )
    }

    private func obtainThread(
        forceNew: Bool,
        selection: SelectionSnapshot
    ) async throws -> String {
        if !forceNew,
            preferences.threadMode == .reuseFixed,
            let stored = preferences.fixedThreadID
        {
            do {
                return try await attachThread(id: stored)
            } catch let error as AppServerProtocolError {
                guard Self.isMissingThread(error) else {
                    throw error
                }
                preferences.resetFixedThread()
            }
        }

        let identifier = try await client.startThread(
            model: currentChoice.model,
            serviceTier: currentChoice.serviceTier,
            workingDirectory: GlossletConstants.defaultWorkspaceURL,
            persistent: true
        )
        await markThreadAttached(identifier)
        if preferences.threadMode == .reuseFixed {
            preferences.useFixedThread(identifier)
        }
        let name = taskName(
            for: selection,
            isFixed: preferences.threadMode == .reuseFixed
        )
        try? await client.setThreadName(
            threadID: identifier,
            name: name
        )
        return identifier
    }

    private func attachThread(id threadID: String) async throws -> String {
        let action = await validatedAttachmentAction(for: threadID)
        guard action != .reuse else {
            return threadID
        }
        if latencyTrace != nil {
            requestAwaitsCodexPreparation = true
        }

        if attachingThreadID == threadID, let attachmentTask {
            recordLatencyPhase("thread_attach_waiting")
            let identifier = try await attachmentTask.value
            recordLatencyPhase("thread_attach_completed")
            await markThreadAttached(identifier)
            threadPreparationExpectedUntil = Date()
                .addingTimeInterval(20)
            return identifier
        }

        if action == .reload {
            threadAttachment.markProcessTerminated()
        }
        recordLatencyPhase(
            action == .reload
                ? "thread_reload_sent"
                : "thread_resume_sent"
        )
        let choice = currentChoice
        let task = Task { [client] in
            switch action {
            case .reuse:
                return threadID
            case .resume:
                return try await client.resumeThread(
                    id: threadID,
                    model: choice.model,
                    serviceTier: choice.serviceTier,
                    workingDirectory:
                        GlossletConstants.defaultWorkspaceURL
                )
            case .reload:
                return try await client.reloadThreadFromDisk(
                    id: threadID,
                    model: choice.model,
                    serviceTier: choice.serviceTier,
                    workingDirectory:
                        GlossletConstants.defaultWorkspaceURL
                )
            }
        }
        attachingThreadID = threadID
        attachmentTask = task
        defer {
            if attachingThreadID == threadID {
                attachingThreadID = nil
                attachmentTask = nil
            }
        }
        let identifier = try await task.value
        recordLatencyPhase(
            action == .reload
                ? "thread_reload_completed"
                : "thread_resume_completed"
        )
        await markThreadAttached(identifier)
        threadPreparationExpectedUntil = Date().addingTimeInterval(20)
        return identifier
    }

    private func validatedAttachmentAction(
        for threadID: String
    ) async -> ThreadAttachmentAction {
        let action = threadAttachment.action(for: threadID)
        guard action == .reuse else {
            return action
        }
        let connection = await client.connectionStatus()
        guard connection.isReady,
            connection.generation == attachedConnectionGeneration
        else {
            threadAttachment.markProcessTerminated()
            attachedConnectionGeneration = nil
            return .resume
        }
        return .reuse
    }

    private func markThreadAttached(_ threadID: String) async {
        let connection = await client.connectionStatus()
        threadAttachment.markAttached(threadID)
        attachedConnectionGeneration = connection.generation
    }

    private func taskName(
        for selection: SelectionSnapshot,
        isFixed: Bool
    ) -> String {
        if isFixed {
            return L10n.text(
                "Glosslet — Quick explanations",
                "Glosslet — 随手解释"
            )
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, HH:mm"
        return "Glosslet — \(selection.sourceApplicationName) — "
            + formatter.string(from: Date())
    }

    private func appendStreamingAssistant(activityText: String) {
        discardPendingDelta()
        let identifier = UUID()
        messages.append(
            ConversationMessage(
                id: identifier,
                role: .assistant,
                text: "",
                isStreaming: true,
                activityText: activityText,
                startedAt: requestStartedAt
            )
        )
        activeAssistantMessageID = identifier
    }

    private func beginLatencyTrace(kind: String) {
        requestAwaitsCodexPreparation = false
        let trace = CodexRequestLatencyTrace(kind: kind)
        latencyTrace = trace
        latencyLogger.info(
            "request=\(trace.identifier, privacy: .public) kind=\(trace.kind, privacy: .public) phase=started elapsed_ms=0"
        )
    }

    private func recordLatencyPhase(_ phase: String) {
        guard let trace = latencyTrace else {
            return
        }
        let elapsedMilliseconds = Self.milliseconds(
            since: trace.startedAt
        )
        latencyLogger.info(
            "request=\(trace.identifier, privacy: .public) kind=\(trace.kind, privacy: .public) phase=\(phase, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public)"
        )
    }

    private func recordFirstContentIfNeeded() {
        guard var trace = latencyTrace,
            !trace.didRecordFirstContent
        else {
            return
        }
        trace.didRecordFirstContent = true
        latencyTrace = trace
        recordLatencyPhase("first_content")
    }

    private func recordTokenUsage(
        inputTokens: Int,
        cachedInputTokens: Int
    ) {
        guard var trace = latencyTrace else {
            return
        }
        trace.inputTokens = inputTokens
        trace.cachedInputTokens = cachedInputTokens
        latencyTrace = trace
        let cachePercent =
            inputTokens > 0
            ? Int(
                (Double(cachedInputTokens) / Double(inputTokens) * 100)
                    .rounded()
            )
            : 0
        latencyLogger.info(
            "request=\(trace.identifier, privacy: .public) phase=token_usage input_tokens=\(inputTokens, privacy: .public) cached_input_tokens=\(cachedInputTokens, privacy: .public) cache_percent=\(cachePercent, privacy: .public)"
        )
    }

    private func finishLatencyTrace(outcome: String) {
        guard let trace = latencyTrace else {
            return
        }
        let elapsedMilliseconds = Self.milliseconds(
            since: trace.startedAt
        )
        let inputTokens = trace.inputTokens ?? -1
        let cachedInputTokens = trace.cachedInputTokens ?? -1
        latencyLogger.info(
            "request=\(trace.identifier, privacy: .public) kind=\(trace.kind, privacy: .public) phase=finished outcome=\(outcome, privacy: .public) elapsed_ms=\(elapsedMilliseconds, privacy: .public) input_tokens=\(inputTokens, privacy: .public) cached_input_tokens=\(cachedInputTokens, privacy: .public)"
        )
        latencyTrace = nil
        requestAwaitsCodexPreparation = false
    }

    private static func milliseconds(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) * 1_000))
    }

    private func updateAssistantActivity(_ activityText: String) {
        statusText = activityText
        guard let identifier = activeAssistantMessageID,
            let index = messages.firstIndex(where: {
                $0.id == identifier
            })
        else {
            return
        }
        messages[index].activityText = activityText
    }

    private func appendDelta(_ delta: String, itemID: String) {
        streamedItemIDs.insert(itemID)
        pendingAssistantDelta += delta
        guard deltaFlushTask == nil else {
            return
        }
        deltaFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(32))
            } catch {
                return
            }
            guard !Task.isCancelled, let self else {
                return
            }
            deltaFlushTask = nil
            flushPendingDelta()
        }
    }

    private func flushPendingDelta() {
        deltaFlushTask?.cancel()
        deltaFlushTask = nil
        guard !pendingAssistantDelta.isEmpty else {
            return
        }
        let delta = pendingAssistantDelta
        pendingAssistantDelta = ""
        guard let identifier = activeAssistantMessageID,
            let index = messages.firstIndex(where: {
                $0.id == identifier
            })
        else {
            return
        }
        messages[index].text += delta
    }

    private func discardPendingDelta() {
        deltaFlushTask?.cancel()
        deltaFlushTask = nil
        pendingAssistantDelta = ""
    }

    private func finishStreamingMessage(finalText: String? = nil) {
        flushPendingDelta()
        guard let identifier = activeAssistantMessageID,
            let index = messages.firstIndex(where: {
                $0.id == identifier
            })
        else {
            return
        }
        if messages[index].text.isEmpty,
            let finalText,
            !finalText.isEmpty
        {
            messages[index].text = finalText
        }
        messages[index].isStreaming = false
        messages[index].activityText = nil
        activeAssistantMessageID = nil
    }

    private func fail(_ error: Error) {
        finishStreamingMessage()
        activeTurnID = nil
        isBusy = false
        errorMessage = error.localizedDescription
        if let requestStartedAt {
            statusText = L10n.failedIn(
                Date().timeIntervalSince(requestStartedAt)
            )
        } else {
            statusText = L10n.text("Couldn’t complete", "未能完成")
        }
        finishLatencyTrace(outcome: "failed")
        requestStartedAt = nil
    }

    private func handle(_ event: AppServerEvent) {
        switch event {
        case .turnStarted(let eventThreadID, let turnID):
            guard isBusy,
                eventThreadID == threadID,
                activeTurnID == nil || activeTurnID == turnID
            else {
                return
            }
            activeTurnID = turnID
            recordLatencyPhase("turn_started")
            updateAssistantActivity(
                requestAwaitsCodexPreparation
                    ? L10n.preparingCodex
                    : L10n.thinking
            )

        case .itemStarted(let eventThreadID, let turnID, let item):
            guard isBusy,
                eventThreadID == threadID,
                activeTurnID == nil || activeTurnID == turnID
            else {
                return
            }
            if item.type == "contextCompaction" {
                updateAssistantActivity(L10n.optimizingTask)
                return
            }
            requestAwaitsCodexPreparation = false
            if item.type == "agentMessage" {
                updateAssistantActivity(L10n.writingResponse)
            } else if item.type == "reasoning" {
                updateAssistantActivity(L10n.thinking)
            }

        case .agentMessageDelta(
            let eventThreadID,
            let turnID,
            let itemID,
            let delta
        ):
            guard isBusy,
                eventThreadID == threadID,
                activeTurnID == nil || activeTurnID == turnID
            else {
                return
            }
            requestAwaitsCodexPreparation = false
            recordFirstContentIfNeeded()
            updateAssistantActivity(L10n.writingResponse)
            appendDelta(delta, itemID: itemID)

        case .itemCompleted(
            let eventThreadID,
            let turnID,
            let item
        ):
            guard isBusy,
                eventThreadID == threadID,
                activeTurnID == nil || activeTurnID == turnID,
                item.type == "agentMessage"
            else {
                return
            }
            if item.text?.isEmpty == false {
                recordFirstContentIfNeeded()
            }
            finishStreamingMessage(finalText: item.text)

        case .turnCompleted(
            let eventThreadID,
            let turnID,
            let status,
            let eventError
        ):
            guard isBusy,
                eventThreadID == threadID,
                activeTurnID == nil || activeTurnID == turnID
            else {
                return
            }
            finishStreamingMessage()
            activeTurnID = nil
            isBusy = false
            if status == "completed" {
                if let requestStartedAt {
                    statusText = L10n.completedIn(
                        Date().timeIntervalSince(requestStartedAt)
                    )
                } else {
                    statusText = L10n.done
                }
            } else if status == "interrupted" {
                statusText = L10n.stopped
            } else {
                statusText = L10n.text("Turn \(status)", "任务状态：\(status)")
            }
            if let eventError, !eventError.isEmpty {
                errorMessage = eventError
            }
            if status == "completed" {
                threadPreparationExpectedUntil = nil
            }
            finishLatencyTrace(outcome: status)
            requestStartedAt = nil

        case .tokenUsageUpdated(
            let eventThreadID,
            let turnID,
            let inputTokens,
            let cachedInputTokens
        ):
            guard isBusy,
                eventThreadID == threadID,
                activeTurnID == nil || activeTurnID == turnID
            else {
                return
            }
            recordTokenUsage(
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens
            )

        case .serverRequest(let request):
            pendingApproval = PendingApproval(
                request: request,
                title: L10n.approval,
                detail: Self.approvalDetail(for: request)
            )

        case .warning(let warning):
            if errorMessage == nil {
                errorMessage = warning
            }

        case .processTerminated(let details):
            threadAttachment.markProcessTerminated()
            attachedConnectionGeneration = nil
            lastRuntimePrewarmAt = nil
            if isBusy {
                fail(
                    AppServerProtocolError.invalidResponse(
                        details
                            ?? L10n.text(
                                "Codex stopped unexpectedly.",
                                "Codex 意外停止。"
                            )
                    )
                )
            }
            scheduleRecovery(
                trigger: .processTerminated,
                waitForPreferredControlSocket: true
            )

        case .notification:
            break
        }
    }

    private static func isMissingThread(
        _ error: AppServerProtocolError
    ) -> Bool {
        guard case .rpcError(_, let message) = error else {
            return false
        }
        let lowercased = message.lowercased()
        return lowercased.contains("not found")
            || lowercased.contains("does not exist")
            || lowercased.contains("unknown thread")
    }

    private static func isRetryableRecoveryError(
        _ error: AppServerProtocolError
    ) -> Bool {
        switch error {
        case .processUnavailable, .requestTimedOut, .rpcError:
            return true
        case .codexBinaryNotFound, .codexNotAuthenticated,
            .responseMissingResult, .invalidResponse:
            return false
        }
    }

    private static func approvalDetail(
        for request: AppServerRequest
    ) -> String {
        if let reason = request.params["reason"]?.stringValue,
            !reason.isEmpty
        {
            return reason
        }
        if let command = request.params["command"]?.stringValue {
            return command
        }
        if let command = request.params["command"]?.arrayValue {
            let text = command.compactMap(\.stringValue).joined(separator: " ")
            if !text.isEmpty {
                return text
            }
        }
        if let grantRoot = request.params["grantRoot"]?.stringValue {
            return grantRoot
        }
        return request.method
    }

    private static func approvalResult(
        for request: AppServerRequest,
        allow: Bool,
        forSession: Bool
    ) -> JSONValue {
        switch request.method {
        case "item/commandExecution/requestApproval",
            "item/fileChange/requestApproval":
            return .object([
                "decision": .string(
                    allow
                        ? (forSession ? "acceptForSession" : "accept")
                        : "decline"
                )
            ])

        case "item/permissions/requestApproval":
            return .object([
                "permissions": allow
                    ? (request.params["permissions"] ?? .object([:]))
                    : .object([:]),
                "scope": .string(forSession ? "session" : "turn"),
            ])

        case "execCommandApproval", "applyPatchApproval":
            return .object([
                "decision": .string(
                    allow
                        ? (forSession
                            ? "approved_for_session"
                            : "approved")
                        : "abort"
                )
            ])

        default:
            return .object([
                "decision": .string(allow ? "accept" : "decline")
            ])
        }
    }
}
