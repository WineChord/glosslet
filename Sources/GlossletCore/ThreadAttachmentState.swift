import Foundation

public enum ThreadAttachmentAction: Equatable, Sendable {
    case reuse
    case resume
    case reload
}

public struct ThreadAttachmentState: Equatable, Sendable {
    public private(set) var attachedThreadID: String?
    public private(set) var externalHistoryMayHaveChanged = false

    public init() {}

    public func action(for threadID: String) -> ThreadAttachmentAction {
        guard attachedThreadID == threadID else {
            return .resume
        }
        return externalHistoryMayHaveChanged ? .reload : .reuse
    }

    public mutating func markAttached(_ threadID: String) {
        attachedThreadID = threadID
        externalHistoryMayHaveChanged = false
    }

    public mutating func markExternalHistoryMayHaveChanged() {
        guard attachedThreadID != nil else {
            return
        }
        externalHistoryMayHaveChanged = true
    }

    public mutating func markProcessTerminated() {
        attachedThreadID = nil
        externalHistoryMayHaveChanged = false
    }
}
