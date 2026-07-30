import CoreGraphics
import Foundation

public struct SelectionSnapshot: Equatable, Sendable {
    public let text: String
    public let sourceApplicationName: String
    public let sourceBundleIdentifier: String?
    public let sourceProcessIdentifier: Int32
    public let bounds: CGRect
    public let anchorBounds: CGRect
    public let capturedAt: Date

    public init(
        text: String,
        sourceApplicationName: String,
        sourceBundleIdentifier: String?,
        sourceProcessIdentifier: Int32,
        bounds: CGRect,
        anchorBounds: CGRect? = nil,
        capturedAt: Date = Date()
    ) {
        self.text = text
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.bounds = bounds
        self.anchorBounds = anchorBounds ?? bounds
        self.capturedAt = capturedAt
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isUsable: Bool {
        !trimmedText.isEmpty
    }

    public var isWithinExplanationLimit: Bool {
        text.count <= GlossletConstants.maximumSelectionCharacters
    }

    public var preview: String {
        let normalized = trimmedText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        guard normalized.count > 240 else {
            return normalized
        }
        return String(normalized.prefix(237)) + "…"
    }

    public func representsSameSelection(as other: SelectionSnapshot) -> Bool {
        text == other.text
            && sourceProcessIdentifier == other.sourceProcessIdentifier
            && bounds.integral == other.bounds.integral
    }
}

public enum SelectionValidationError: LocalizedError, Equatable {
    case empty
    case tooLong(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Select some text first."
        case .tooLong(let maximum):
            return "The selection is too long. Select at most \(maximum) characters."
        }
    }
}

public enum SelectionValidator {
    public static func validate(_ snapshot: SelectionSnapshot) throws {
        guard snapshot.isUsable else {
            throw SelectionValidationError.empty
        }
        guard snapshot.isWithinExplanationLimit else {
            throw SelectionValidationError.tooLong(
                maximum: GlossletConstants.maximumSelectionCharacters
            )
        }
    }
}
