import Foundation
import XCTest

@testable import GlossletCore

final class CodexAppServerIntegrationTests: XCTestCase {
    func testConcurrentModelRequestsShareConnection() async throws {
        guard
            ProcessInfo.processInfo.environment[
                "GLOSSLET_RUN_CODEX_INTEGRATION"
            ] == "1"
        else {
            throw XCTSkip(
                "Set GLOSSLET_RUN_CODEX_INTEGRATION=1 to run against Codex."
            )
        }

        let client = CodexAppServerClient()
        async let firstModels = client.listModels()
        async let secondModels = client.listModels()
        let (first, second) = try await (firstModels, secondModels)

        await client.shutdown()
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testReconnectResumesPersistentThreadOnNewConnection() async throws {
        guard
            ProcessInfo.processInfo.environment[
                "GLOSSLET_RUN_CODEX_INTEGRATION"
            ] == "1"
        else {
            throw XCTSkip(
                "Set GLOSSLET_RUN_CODEX_INTEGRATION=1 to run against Codex."
            )
        }

        let client = CodexAppServerClient()
        let stream = await client.eventStream()
        let models = try await client.listModels()
        let choice = ModelSelection.recommended(from: models)
        XCTAssertNotNil(choice.model)
        XCTAssertEqual(choice.reasoningEffort, "low")
        XCTAssertEqual(choice.serviceTier, "priority")
        let workspace = GlossletConstants.defaultWorkspaceURL
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        let initialStatus = await client.connectionStatus()
        let threadID = try await client.startThread(
            model: choice.model,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace,
            persistent: true
        )
        let continuityMarker =
            "GLOSSLET_RECOVERY_\(UUID().uuidString.prefix(8))"
        let firstResult = try await Self.runTurn(
            client: client,
            stream: stream,
            threadID: threadID,
            text:
                "Remember \(continuityMarker) for the next turn. "
                + "Reply with exactly READY.",
            choice: choice,
            workspace: workspace
        )
        XCTAssertTrue(firstResult.contains("READY"), firstResult)

        await client.shutdown()
        let disconnectedStatus = await client.connectionStatus()
        XCTAssertFalse(disconnectedStatus.isReady)
        XCTAssertEqual(
            disconnectedStatus.lastTransport,
            initialStatus.transport
        )

        let resumeStartedAt = Date()
        let resumedID = try await client.resumeThread(
            id: threadID,
            model: choice.model,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace
        )
        let resumeDuration = Date().timeIntervalSince(resumeStartedAt)
        let reconnectedStatus = await client.connectionStatus()

        XCTAssertEqual(resumedID, threadID)
        XCTAssertTrue(reconnectedStatus.isReady)
        XCTAssertNotEqual(
            reconnectedStatus.generation,
            initialStatus.generation
        )
        let recoveredTurnStartedAt = Date()
        let recoveredResult = try await Self.runTurn(
            client: client,
            stream: stream,
            threadID: threadID,
            text:
                "Reply with exactly the marker from my previous message "
                + "and nothing else.",
            choice: choice,
            workspace: workspace
        )
        let recoveredTurnDuration = Date().timeIntervalSince(
            recoveredTurnStartedAt
        )
        XCTAssertTrue(
            recoveredResult.contains(continuityMarker),
            recoveredResult
        )
        print(
            "GLOSSLET_RECOVERY_RESUME_SECONDS="
                + String(format: "%.3f", resumeDuration)
        )
        print(
            "GLOSSLET_RECOVERY_TURN_SECONDS="
                + String(format: "%.3f", recoveredTurnDuration)
        )
        try await client.archiveThread(threadID: threadID)
        await client.shutdown()
    }

    func testPersistentThreadStreamsAndCompletes() async throws {
        guard
            ProcessInfo.processInfo.environment[
                "GLOSSLET_RUN_CODEX_INTEGRATION"
            ] == "1"
        else {
            throw XCTSkip(
                "Set GLOSSLET_RUN_CODEX_INTEGRATION=1 to run against Codex."
            )
        }

        let client = CodexAppServerClient()
        let stream = await client.eventStream()
        let models = try await client.listModels()
        let choice = ModelSelection.recommended(from: models)
        let workspace = GlossletConstants.defaultWorkspaceURL
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )

        let threadID = try await client.startThread(
            model: choice.model,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace,
            persistent: true
        )
        let marker = "GLOSSLET_OK_\(UUID().uuidString.prefix(8))"
        try await client.setThreadName(
            threadID: threadID,
            name: "Glosslet — Integration check"
        )

        let resultTask = Task {
            try await Self.collectCompletion(
                from: stream,
                threadID: threadID
            )
        }
        _ = try await client.startTurn(
            threadID: threadID,
            text: "Reply with exactly \(marker) and nothing else.",
            model: choice.model,
            reasoningEffort: choice.reasoningEffort,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace
        )

        let result = try await withThrowingTaskGroup(
            of: String.self
        ) { group in
            group.addTask {
                try await resultTask.value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(120))
                throw AppServerProtocolError.requestTimedOut
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        await client.shutdown()
        print("GLOSSLET_INTEGRATION_THREAD_ID=\(threadID)")
        print("GLOSSLET_INTEGRATION_MODEL=\(choice.model ?? "default")")
        print(
            "GLOSSLET_INTEGRATION_EFFORT="
                + (choice.reasoningEffort ?? "default")
        )
        XCTAssertTrue(result.contains(marker), result)
    }

    func testPriorityThreadReusesNativeContextAndContinues() async throws {
        guard
            ProcessInfo.processInfo.environment[
                "GLOSSLET_RUN_CODEX_INTEGRATION"
            ] == "1"
        else {
            throw XCTSkip(
                "Set GLOSSLET_RUN_CODEX_INTEGRATION=1 to run against Codex."
            )
        }

        let client = CodexAppServerClient()
        let stream = await client.eventStream()
        let models = try await client.listModels()
        let choice = ModelSelection.recommended(from: models)
        let workspace = GlossletConstants.defaultWorkspaceURL
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )

        XCTAssertNotNil(choice.model)
        XCTAssertNotNil(choice.reasoningEffort)
        XCTAssertEqual(choice.serviceTier, "priority")

        let threadID = try await client.startThread(
            model: choice.model,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace,
            persistent: true
        )
        try await client.setThreadName(
            threadID: threadID,
            name: "Glosslet — Native reuse integration check"
        )
        await client.prewarmRuntime(
            workingDirectory: workspace,
            threadID: threadID
        )

        do {
            let continuityMarker =
                "GLOSSLET_REUSE_\(UUID().uuidString.prefix(8))"
            let first = try await Self.runTurn(
                client: client,
                stream: stream,
                threadID: threadID,
                text:
                    "Remember this continuity marker for the next turn: "
                    + "\(continuityMarker). Reply with exactly READY.",
                choice: choice,
                workspace: workspace
            )
            XCTAssertTrue(first.contains("READY"), first)

            let second = try await Self.runTurn(
                client: client,
                stream: stream,
                threadID: threadID,
                text:
                    "Reply with exactly the continuity marker from my "
                    + "previous message and nothing else.",
                choice: choice,
                workspace: workspace
            )
            XCTAssertTrue(second.contains(continuityMarker), second)
        } catch {
            try? await client.archiveThread(threadID: threadID)
            await client.shutdown()
            throw error
        }

        try await client.archiveThread(threadID: threadID)
        await client.shutdown()
        print("GLOSSLET_REUSE_THREAD_ID=\(threadID)")
        print("GLOSSLET_REUSE_MODEL=\(choice.model ?? "default")")
        print(
            "GLOSSLET_REUSE_EFFORT="
                + (choice.reasoningEffort ?? "default")
        )
        print(
            "GLOSSLET_REUSE_SERVICE_TIER="
                + (choice.serviceTier ?? "default")
        )
    }

    func testResumeCodexAppThreadAndContinueStreaming() async throws {
        guard
            let threadID = ProcessInfo.processInfo.environment[
                "GLOSSLET_RESUME_THREAD_ID"
            ], !threadID.isEmpty
        else {
            throw XCTSkip(
                "Set GLOSSLET_RESUME_THREAD_ID to exercise two-way continuation."
            )
        }

        let client = CodexAppServerClient()
        let stream = await client.eventStream()
        let models = try await client.listModels()
        let choice = ModelSelection.recommended(from: models)
        let workspace = GlossletConstants.defaultWorkspaceURL
        let resumedID = try await client.resumeThread(
            id: threadID,
            model: choice.model,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace
        )
        XCTAssertEqual(resumedID, threadID)

        let marker = "GLOSSLET_RESUME_OK_\(UUID().uuidString.prefix(8))"
        let resultTask = Task {
            try await Self.collectCompletion(
                from: stream,
                threadID: threadID
            )
        }
        _ = try await client.startTurn(
            threadID: threadID,
            text: "Reply with exactly \(marker) and nothing else.",
            model: choice.model,
            reasoningEffort: choice.reasoningEffort,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace
        )

        let result = try await withThrowingTaskGroup(
            of: String.self
        ) { group in
            group.addTask {
                try await resultTask.value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(120))
                throw AppServerProtocolError.requestTimedOut
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        await client.shutdown()
        print("GLOSSLET_RESUMED_THREAD_ID=\(threadID)")
        print("GLOSSLET_RESUME_MARKER=\(marker)")
        XCTAssertTrue(result.contains(marker), result)
    }

    func testReloadThreadObservesTurnsFromAnotherClient() async throws {
        guard
            ProcessInfo.processInfo.environment[
                "GLOSSLET_RUN_CODEX_INTEGRATION"
            ] == "1"
        else {
            throw XCTSkip(
                "Set GLOSSLET_RUN_CODEX_INTEGRATION=1 to run against Codex."
            )
        }

        let firstClient = CodexAppServerClient()
        let firstStream = await firstClient.eventStream()
        let models = try await firstClient.listModels()
        let choice = ModelSelection.recommended(from: models)
        let workspace = GlossletConstants.defaultWorkspaceURL
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )

        let threadID = try await firstClient.startThread(
            model: choice.model,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace,
            persistent: true
        )
        let initialMarker = "GLOSSLET_INITIAL_\(UUID().uuidString.prefix(8))"
        _ = try await Self.runTurn(
            client: firstClient,
            stream: firstStream,
            threadID: threadID,
            text: "Reply with exactly \(initialMarker) and nothing else.",
            choice: choice,
            workspace: workspace
        )

        let secondClient = CodexAppServerClient()
        let secondStream = await secondClient.eventStream()
        _ = try await secondClient.resumeThread(
            id: threadID,
            model: choice.model,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace
        )
        let externalMarker = "CODEX_SIDE_\(UUID().uuidString.prefix(8))"
        let externalResult = try await Self.runTurn(
            client: secondClient,
            stream: secondStream,
            threadID: threadID,
            text: "Reply with exactly \(externalMarker) and nothing else.",
            choice: choice,
            workspace: workspace
        )
        XCTAssertTrue(externalResult.contains(externalMarker), externalResult)

        let reloadedID = try await firstClient.reloadThreadFromDisk(
            id: threadID,
            model: choice.model,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace
        )
        XCTAssertEqual(reloadedID, threadID)
        let observedResult = try await Self.runTurn(
            client: firstClient,
            stream: firstStream,
            threadID: threadID,
            text:
                "Return exactly the token from the immediately preceding "
                + "assistant response and nothing else.",
            choice: choice,
            workspace: workspace
        )

        await firstClient.shutdown()
        await secondClient.shutdown()
        print("GLOSSLET_CROSS_SURFACE_THREAD_ID=\(threadID)")
        print("GLOSSLET_CROSS_SURFACE_MARKER=\(externalMarker)")
        XCTAssertTrue(observedResult.contains(externalMarker), observedResult)
    }

    private static func runTurn(
        client: CodexAppServerClient,
        stream: AsyncStream<AppServerEvent>,
        threadID: String,
        text: String,
        choice: ModelChoice,
        workspace: URL
    ) async throws -> String {
        let resultTask = Task {
            try await collectCompletion(
                from: stream,
                threadID: threadID
            )
        }
        _ = try await client.startTurn(
            threadID: threadID,
            text: text,
            model: choice.model,
            reasoningEffort: choice.reasoningEffort,
            serviceTier: choice.serviceTier,
            workingDirectory: workspace
        )

        return try await withThrowingTaskGroup(
            of: String.self
        ) { group in
            group.addTask {
                try await resultTask.value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(120))
                throw AppServerProtocolError.requestTimedOut
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private static func withTimeout(
        _ task: Task<String, Error>
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await task.value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(120))
                throw AppServerProtocolError.requestTimedOut
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private static func collectCompletion(
        from stream: AsyncStream<AppServerEvent>,
        threadID: String
    ) async throws -> String {
        var output = ""
        for await event in stream {
            switch event {
            case .agentMessageDelta(
                let eventThreadID,
                _,
                _,
                let delta
            ) where eventThreadID == threadID:
                output += delta

            case .itemCompleted(
                let eventThreadID,
                _,
                let item
            )
            where eventThreadID == threadID
                && item.type == "agentMessage"
                && output.isEmpty:
                output = item.text ?? output

            case .turnCompleted(
                let eventThreadID,
                _,
                let status,
                let error
            ) where eventThreadID == threadID:
                guard status == "completed" else {
                    throw AppServerProtocolError.invalidResponse(
                        error ?? "Turn finished with status \(status)."
                    )
                }
                return output

            case .processTerminated(let details):
                throw AppServerProtocolError.invalidResponse(
                    details ?? "Codex app server stopped."
                )

            default:
                continue
            }
        }
        throw AppServerProtocolError.processUnavailable
    }
}
