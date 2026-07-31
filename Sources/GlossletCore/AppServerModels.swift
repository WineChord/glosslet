import Foundation

public struct ReasoningEffortOption: Equatable, Sendable {
    public let effort: String
    public let description: String

    public init(effort: String, description: String) {
        self.effort = effort
        self.description = description
    }
}

public struct CodexServiceTier: Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String

    public init(id: String, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct CodexModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let model: String
    public let displayName: String
    public let description: String
    public let hidden: Bool
    public let isDefault: Bool
    public let defaultReasoningEffort: String
    public let supportedReasoningEfforts: [ReasoningEffortOption]
    public let serviceTiers: [CodexServiceTier]
    public let defaultServiceTier: String?

    public init(
        id: String,
        model: String,
        displayName: String,
        description: String,
        hidden: Bool,
        isDefault: Bool,
        defaultReasoningEffort: String,
        supportedReasoningEfforts: [ReasoningEffortOption],
        serviceTiers: [CodexServiceTier] = [],
        defaultServiceTier: String? = nil
    ) {
        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.hidden = hidden
        self.isDefault = isDefault
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.serviceTiers = serviceTiers
        self.defaultServiceTier = defaultServiceTier
    }

    public init(json: JSONValue) throws {
        guard let id = json["id"]?.stringValue,
            let model = json["model"]?.stringValue,
            let displayName = json["displayName"]?.stringValue,
            let description = json["description"]?.stringValue,
            let hidden = json["hidden"]?.boolValue,
            let isDefault = json["isDefault"]?.boolValue,
            let defaultEffort = json["defaultReasoningEffort"]?.stringValue,
            let effortValues = json["supportedReasoningEfforts"]?.arrayValue
        else {
            throw AppServerProtocolError.invalidResponse(
                "A model catalog entry was incomplete."
            )
        }

        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.hidden = hidden
        self.isDefault = isDefault
        defaultReasoningEffort = defaultEffort
        supportedReasoningEfforts = effortValues.compactMap { value in
            guard let effort = value["reasoningEffort"]?.stringValue else {
                return nil
            }
            return ReasoningEffortOption(
                effort: effort,
                description: value["description"]?.stringValue ?? effort
            )
        }
        serviceTiers =
            json["serviceTiers"]?.arrayValue?.compactMap { value in
                guard let id = value["id"]?.stringValue else {
                    return nil
                }
                return CodexServiceTier(
                    id: id,
                    name: value["name"]?.stringValue ?? id,
                    description: value["description"]?.stringValue ?? ""
                )
            } ?? []
        defaultServiceTier = json["defaultServiceTier"]?.stringValue
    }
}

public struct ModelChoice: Equatable, Sendable {
    public let model: String?
    public let displayName: String
    public let reasoningEffort: String?
    public let serviceTier: String?

    public init(
        model: String?,
        displayName: String,
        reasoningEffort: String?,
        serviceTier: String? = nil
    ) {
        self.model = model
        self.displayName = displayName
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
    }
}

public struct AppServerItem: Equatable, Sendable {
    public let id: String
    public let type: String
    public let text: String?
    public let phase: String?

    public init(id: String, type: String, text: String?, phase: String?) {
        self.id = id
        self.type = type
        self.text = text
        self.phase = phase
    }

    public init?(json: JSONValue) {
        guard let id = json["id"]?.stringValue,
            let type = json["type"]?.stringValue
        else {
            return nil
        }
        self.id = id
        self.type = type
        text = json["text"]?.stringValue
        phase = json["phase"]?.stringValue
    }
}

public struct AppServerRequest: Equatable, Sendable {
    public let id: JSONValue
    public let method: String
    public let params: JSONValue

    public init(id: JSONValue, method: String, params: JSONValue) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public enum AppServerEvent: Equatable, Sendable {
    case turnStarted(threadID: String, turnID: String)
    case itemStarted(threadID: String, turnID: String, item: AppServerItem)
    case agentMessageDelta(
        threadID: String,
        turnID: String,
        itemID: String,
        delta: String
    )
    case itemCompleted(threadID: String, turnID: String, item: AppServerItem)
    case turnCompleted(
        threadID: String,
        turnID: String,
        status: String,
        errorMessage: String?
    )
    case tokenUsageUpdated(
        threadID: String,
        turnID: String,
        inputTokens: Int,
        cachedInputTokens: Int
    )
    case serverRequest(AppServerRequest)
    case warning(String)
    case processTerminated(String?)
    case notification(method: String, params: JSONValue)
}

public enum AppServerProtocolError: LocalizedError, Equatable {
    case codexBinaryNotFound
    case codexNotAuthenticated
    case processUnavailable
    case requestTimedOut
    case responseMissingResult
    case invalidResponse(String)
    case rpcError(code: Int?, message: String)

    public var errorDescription: String? {
        switch self {
        case .codexBinaryNotFound:
            return "The Codex executable could not be found."
        case .codexNotAuthenticated:
            return "Codex is not signed in. Open the Codex app, then try again."
        case .processUnavailable:
            return "The Codex app server is unavailable."
        case .requestTimedOut:
            return "The Codex app server did not respond in time."
        case .responseMissingResult:
            return "The Codex app server returned no result."
        case .invalidResponse(let message):
            return message
        case .rpcError(_, let message):
            return message
        }
    }
}
