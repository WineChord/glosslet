import Foundation

public actor CodexAppServerClient {
    private struct OutgoingRequest: Encodable {
        let id: Int
        let method: String
        let params: JSONValue?
    }

    private struct OutgoingNotification: Encodable {
        let method: String
        let params: JSONValue?
    }

    private struct OutgoingResponse: Encodable {
        let id: JSONValue
        let result: JSONValue?
        let error: OutgoingError?
    }

    private struct OutgoingError: Encodable {
        let code: Int
        let message: String
    }

    private let binaryURLProvider: @Sendable () -> URL?
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var standardErrorTail = Data()
    private var nextRequestID = 1
    private var processGeneration = 0
    private var initialized = false
    private var connectionTask: Task<Void, Error>?
    private var modelListTask: Task<[CodexModel], Error>?
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var eventContinuations: [UUID: AsyncStream<AppServerEvent>.Continuation] =
        [:]

    public init(
        binaryURLProvider: @escaping @Sendable () -> URL? =
            { CodexBinaryLocator.findBinary() }
    ) {
        self.binaryURLProvider = binaryURLProvider
    }

    deinit {
        process?.terminationHandler = nil
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        process?.terminate()
    }

    public func eventStream() -> AsyncStream<AppServerEvent> {
        let identifier = UUID()
        return AsyncStream { continuation in
            eventContinuations[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeEventContinuation(identifier)
                }
            }
        }
    }

    public func connect() async throws {
        if process?.isRunning == true, initialized {
            return
        }

        if let connectionTask {
            try await connectionTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else {
                throw AppServerProtocolError.processUnavailable
            }
            try await self.establishConnection()
        }
        connectionTask = task
        do {
            try await task.value
            connectionTask = nil
        } catch {
            connectionTask = nil
            throw error
        }
    }

    private func establishConnection() async throws {
        if process?.isRunning == true, initialized {
            return
        }

        try startProcess()
        let initializeResult = try await sendRequest(
            method: "initialize",
            params: .object([
                "clientInfo": .object([
                    "name": .string(GlossletConstants.clientName),
                    "title": .string(GlossletConstants.appName),
                    "version": .string(GlossletConstants.appVersion),
                ]),
                "capabilities": .object([
                    "experimentalApi": .bool(false),
                    "requestAttestation": .bool(false),
                    "optOutNotificationMethods": .array([]),
                ]),
            ])
        )
        guard initializeResult["codexHome"]?.stringValue != nil else {
            shutdown()
            throw AppServerProtocolError.invalidResponse(
                "Codex initialization returned an incomplete response."
            )
        }
        try sendNotification(method: "initialized", params: .object([:]))
        initialized = true
    }

    public func listModels() async throws -> [CodexModel] {
        if let modelListTask {
            return try await modelListTask.value
        }
        let task = Task { [weak self] in
            guard let self else {
                throw AppServerProtocolError.processUnavailable
            }
            return try await self.fetchModels()
        }
        modelListTask = task
        do {
            let models = try await task.value
            modelListTask = nil
            return models
        } catch {
            modelListTask = nil
            throw error
        }
    }

    private func fetchModels() async throws -> [CodexModel] {
        try await connect()
        let result = try await sendRequest(
            method: "model/list",
            params: .object([
                "limit": .number(100),
                "includeHidden": .bool(false),
            ])
        )
        guard let values = result["data"]?.arrayValue else {
            throw AppServerProtocolError.invalidResponse(
                "Codex returned no model catalog."
            )
        }
        return try values.map(CodexModel.init(json:))
    }

    public func prewarmRuntime(
        workingDirectory: URL,
        threadID: String?
    ) async {
        do {
            try await connect()
        } catch {
            return
        }

        async let skills: Void = bestEffortRequest(
            method: "skills/list",
            params: .object([
                "cwds": .array([
                    .string(workingDirectory.path)
                ]),
                "forceReload": .bool(false),
            ])
        )
        async let hooks: Void = bestEffortRequest(
            method: "hooks/list",
            params: .object([
                "cwds": .array([
                    .string(workingDirectory.path)
                ])
            ])
        )
        async let mcp: Void = bestEffortRequest(
            method: "mcpServerStatus/list",
            params: .compactObject([
                "limit": .number(100),
                "detail": .string("toolsAndAuthOnly"),
                "threadId": threadID.map(JSONValue.string),
            ])
        )
        _ = await (skills, hooks, mcp)
    }

    private func bestEffortRequest(
        method: String,
        params: JSONValue
    ) async {
        _ = try? await sendRequest(method: method, params: params)
    }

    public func startThread(
        model: String?,
        serviceTier: String? = nil,
        workingDirectory: URL,
        persistent: Bool = true
    ) async throws -> String {
        try await connect()
        let result = try await sendRequest(
            method: "thread/start",
            params: .compactObject([
                "model": model.map(JSONValue.string),
                "serviceTier": serviceTier.map(JSONValue.string),
                "cwd": .string(workingDirectory.path),
                "ephemeral": .bool(!persistent),
                "threadSource": .string(GlossletConstants.clientName),
            ])
        )
        guard let threadID = result["thread"]?["id"]?.stringValue else {
            throw AppServerProtocolError.invalidResponse(
                "Codex did not return a thread identifier."
            )
        }
        return threadID
    }

    @discardableResult
    public func resumeThread(
        id threadID: String,
        model: String?,
        serviceTier: String? = nil,
        workingDirectory: URL
    ) async throws -> String {
        try await connect()
        let result = try await sendRequest(
            method: "thread/resume",
            params: .compactObject([
                "threadId": .string(threadID),
                "model": model.map(JSONValue.string),
                "serviceTier": serviceTier.map(JSONValue.string),
                "cwd": .string(workingDirectory.path),
            ])
        )
        guard let resumedID = result["thread"]?["id"]?.stringValue else {
            throw AppServerProtocolError.invalidResponse(
                "Codex could not resume the stored thread."
            )
        }
        return resumedID
    }

    /// Restarts the app-server process before resuming so turns added by
    /// another Codex surface are loaded from the persistent task history.
    @discardableResult
    public func reloadThreadFromDisk(
        id threadID: String,
        model: String?,
        serviceTier: String? = nil,
        workingDirectory: URL
    ) async throws -> String {
        shutdown()
        return try await resumeThread(
            id: threadID,
            model: model,
            serviceTier: serviceTier,
            workingDirectory: workingDirectory
        )
    }

    public func setThreadName(
        threadID: String,
        name: String
    ) async throws {
        _ = try await sendRequest(
            method: "thread/name/set",
            params: .object([
                "threadId": .string(threadID),
                "name": .string(name),
            ])
        )
    }

    public func archiveThread(threadID: String) async throws {
        _ = try await sendRequest(
            method: "thread/archive",
            params: .object([
                "threadId": .string(threadID)
            ])
        )
    }

    public func startTurn(
        threadID: String,
        text: String,
        model: String?,
        reasoningEffort: String?,
        serviceTier: String? = nil,
        workingDirectory: URL
    ) async throws -> String {
        try await connect()
        let result = try await sendRequest(
            method: "turn/start",
            params: .compactObject([
                "threadId": .string(threadID),
                "input": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(text),
                    ])
                ]),
                "model": model.map(JSONValue.string),
                "effort": reasoningEffort.map(JSONValue.string),
                "serviceTier": serviceTier.map(JSONValue.string),
                "cwd": .string(workingDirectory.path),
                "clientUserMessageId": .string(UUID().uuidString),
            ])
        )
        guard let turnID = result["turn"]?["id"]?.stringValue else {
            throw AppServerProtocolError.invalidResponse(
                "Codex did not return a turn identifier."
            )
        }
        return turnID
    }

    public func interruptTurn(
        threadID: String,
        turnID: String
    ) async throws {
        _ = try await sendRequest(
            method: "turn/interrupt",
            params: .object([
                "threadId": .string(threadID),
                "turnId": .string(turnID),
            ])
        )
    }

    public func respond(
        to request: AppServerRequest,
        result: JSONValue
    ) throws {
        try write(
            OutgoingResponse(id: request.id, result: result, error: nil)
        )
    }

    public func reject(
        request: AppServerRequest,
        message: String
    ) throws {
        try write(
            OutgoingResponse(
                id: request.id,
                result: nil,
                error: OutgoingError(code: -32_000, message: message)
            )
        )
    }

    public func shutdown() {
        let activeProcess = process
        processGeneration += 1
        activeProcess?.terminationHandler = nil
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil

        process = nil
        inputHandle = nil
        outputHandle = nil
        errorHandle = nil
        initialized = false
        outputBuffer.removeAll(keepingCapacity: false)

        let waiting = pending.values
        pending.removeAll()
        for continuation in waiting {
            continuation.resume(
                throwing: AppServerProtocolError.processUnavailable
            )
        }

        if activeProcess?.isRunning == true {
            activeProcess?.terminate()
        }
    }

    private func startProcess() throws {
        shutdown()
        guard let binaryURL = binaryURLProvider() else {
            throw AppServerProtocolError.codexBinaryNotFound
        }

        processGeneration += 1
        let generation = processGeneration
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let standardError = Pipe()

        process.executableURL = binaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = standardError
        process.terminationHandler = { [weak self] process in
            Task {
                await self?.handleTermination(
                    generation: generation,
                    status: process.terminationStatus
                )
            }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task {
                await self?.handleOutput(data, generation: generation)
            }
        }
        standardError.fileHandleForReading.readabilityHandler = {
            [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task {
                await self?.handleStandardError(
                    data,
                    generation: generation
                )
            }
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            output.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        self.process = process
        inputHandle = input.fileHandleForWriting
        outputHandle = output.fileHandleForReading
        errorHandle = standardError.fileHandleForReading
    }

    private func sendRequest(
        method: String,
        params: JSONValue?
    ) async throws -> JSONValue {
        guard process?.isRunning == true, inputHandle != nil else {
            throw AppServerProtocolError.processUnavailable
        }

        let requestID = nextRequestID
        nextRequestID += 1
        let request = OutgoingRequest(
            id: requestID,
            method: method,
            params: params
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[requestID] = continuation
                do {
                    try write(request)
                } catch {
                    pending.removeValue(forKey: requestID)
                    continuation.resume(throwing: error)
                    return
                }

                Task { [weak self] in
                    try? await Task.sleep(
                        nanoseconds:
                            GlossletConstants.requestTimeoutSeconds
                            * 1_000_000_000
                    )
                    await self?.expireRequest(requestID)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancelRequest(requestID)
            }
        }
    }

    private func sendNotification(
        method: String,
        params: JSONValue?
    ) throws {
        try write(OutgoingNotification(method: method, params: params))
    }

    private func write<T: Encodable>(_ value: T) throws {
        guard let inputHandle, process?.isRunning == true else {
            throw AppServerProtocolError.processUnavailable
        }
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func handleOutput(_ data: Data, generation: Int) {
        guard generation == processGeneration else {
            return
        }
        outputBuffer.append(data)
        let newline = Data([0x0A])
        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(
                in: outputBuffer.startIndex..<range.lowerBound
            )
            outputBuffer.removeSubrange(
                outputBuffer.startIndex..<range.upperBound
            )
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty,
            let value = try? JSONDecoder().decode(
                JSONValue.self,
                from: data
            ),
            let object = value.objectValue
        else {
            return
        }

        if let numericID = object["id"]?.intValue,
            let continuation = pending.removeValue(forKey: numericID)
        {
            if let error = object["error"],
                let message = error["message"]?.stringValue
            {
                continuation.resume(
                    throwing: AppServerProtocolError.rpcError(
                        code: error["code"]?.intValue,
                        message: message
                    )
                )
            } else if let result = object["result"] {
                continuation.resume(returning: result)
            } else {
                continuation.resume(
                    throwing: AppServerProtocolError.responseMissingResult
                )
            }
            return
        }

        guard let method = object["method"]?.stringValue else {
            return
        }
        let params = object["params"] ?? .object([:])
        if let requestID = object["id"] {
            emit(
                .serverRequest(
                    AppServerRequest(
                        id: requestID,
                        method: method,
                        params: params
                    )
                )
            )
            return
        }
        emit(parseNotification(method: method, params: params))
    }

    private func parseNotification(
        method: String,
        params: JSONValue
    ) -> AppServerEvent {
        switch method {
        case "turn/started":
            if let threadID = params["threadId"]?.stringValue,
                let turnID = params["turn"]?["id"]?.stringValue
            {
                return .turnStarted(threadID: threadID, turnID: turnID)
            }
        case "item/started":
            if let threadID = params["threadId"]?.stringValue,
                let turnID = params["turnId"]?.stringValue,
                let itemValue = params["item"],
                let item = AppServerItem(json: itemValue)
            {
                return .itemStarted(
                    threadID: threadID,
                    turnID: turnID,
                    item: item
                )
            }
        case "item/agentMessage/delta":
            if let threadID = params["threadId"]?.stringValue,
                let turnID = params["turnId"]?.stringValue,
                let itemID = params["itemId"]?.stringValue,
                let delta = params["delta"]?.stringValue
            {
                return .agentMessageDelta(
                    threadID: threadID,
                    turnID: turnID,
                    itemID: itemID,
                    delta: delta
                )
            }
        case "item/completed":
            if let threadID = params["threadId"]?.stringValue,
                let turnID = params["turnId"]?.stringValue,
                let itemValue = params["item"],
                let item = AppServerItem(json: itemValue)
            {
                return .itemCompleted(
                    threadID: threadID,
                    turnID: turnID,
                    item: item
                )
            }
        case "turn/completed":
            if let threadID = params["threadId"]?.stringValue,
                let turn = params["turn"],
                let turnID = turn["id"]?.stringValue,
                let status = turn["status"]?.stringValue
            {
                let errorMessage =
                    turn["error"]?["message"]?.stringValue
                    ?? turn["error"]?.stringValue
                return .turnCompleted(
                    threadID: threadID,
                    turnID: turnID,
                    status: status,
                    errorMessage: errorMessage
                )
            }
        case "thread/tokenUsage/updated":
            if let threadID = params["threadId"]?.stringValue,
                let turnID = params["turnId"]?.stringValue,
                let last = params["tokenUsage"]?["last"],
                let inputTokens = last["inputTokens"]?.intValue
            {
                return .tokenUsageUpdated(
                    threadID: threadID,
                    turnID: turnID,
                    inputTokens: inputTokens,
                    cachedInputTokens:
                        last["cachedInputTokens"]?.intValue ?? 0
                )
            }
        case "warning":
            if let message = params["message"]?.stringValue {
                return .warning(message)
            }
        default:
            break
        }
        return .notification(method: method, params: params)
    }

    private func handleStandardError(_ data: Data, generation: Int) {
        guard generation == processGeneration else {
            return
        }
        standardErrorTail.append(data)
        let maximumBytes = 8_192
        if standardErrorTail.count > maximumBytes {
            standardErrorTail.removeFirst(
                standardErrorTail.count - maximumBytes
            )
        }
    }

    private func handleTermination(generation: Int, status: Int32) {
        guard generation == processGeneration else {
            return
        }
        let details = String(
            data: standardErrorTail,
            encoding: .utf8
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        emit(
            .processTerminated(
                details?.isEmpty == false
                    ? details
                    : "Codex app server exited with status \(status)."
            )
        )
        shutdown()
    }

    private func expireRequest(_ requestID: Int) {
        pending.removeValue(forKey: requestID)?.resume(
            throwing: AppServerProtocolError.requestTimedOut
        )
    }

    private func cancelRequest(_ requestID: Int) {
        pending.removeValue(forKey: requestID)?.resume(
            throwing: CancellationError()
        )
    }

    private func removeEventContinuation(_ identifier: UUID) {
        eventContinuations.removeValue(forKey: identifier)
    }

    private func emit(_ event: AppServerEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }
}
