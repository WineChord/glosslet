import CoreGraphics
import Foundation

public struct SelectionSnapshot: Equatable, Sendable {
    public let text: String
    public let sourceApplicationName: String
    public let sourceBundleIdentifier: String?
    public let sourceProcessIdentifier: Int32
    public let sourceElementIdentifier: UInt?
    public let selectionRange: NSRange?
    public let bounds: CGRect
    public let anchorBounds: CGRect
    public let capturedAt: Date

    public init(
        text: String,
        sourceApplicationName: String,
        sourceBundleIdentifier: String?,
        sourceProcessIdentifier: Int32,
        sourceElementIdentifier: UInt? = nil,
        selectionRange: NSRange? = nil,
        bounds: CGRect,
        anchorBounds: CGRect? = nil,
        capturedAt: Date = Date()
    ) {
        self.text = text
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.sourceElementIdentifier = sourceElementIdentifier
        self.selectionRange = selectionRange
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
        guard
            text == other.text,
            sourceProcessIdentifier == other.sourceProcessIdentifier,
            sourceElementIdentifier == other.sourceElementIdentifier
        else {
            return false
        }
        if let selectionRange, let otherRange = other.selectionRange {
            return selectionRange == otherRange
        }
        return bounds.integral == other.bounds.integral
    }

    public func replacingAnchorBounds(_ anchorBounds: CGRect) -> Self {
        Self(
            text: text,
            sourceApplicationName: sourceApplicationName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceProcessIdentifier: sourceProcessIdentifier,
            sourceElementIdentifier: sourceElementIdentifier,
            selectionRange: selectionRange,
            bounds: bounds,
            anchorBounds: anchorBounds,
            capturedAt: capturedAt
        )
    }
}

public struct SelectionAnchorTracker: Sendable {
    private var lastSelection: SelectionSnapshot?

    public init() {}

    public mutating func observe(
        _ candidate: SelectionSnapshot,
        fallbackAnchor: CGRect
    ) -> SelectionSnapshot? {
        guard
            lastSelection?.representsSameSelection(as: candidate) != true
        else {
            return nil
        }

        let anchor: CGRect
        if Self.isUsableAnchor(candidate.anchorBounds) {
            anchor = candidate.anchorBounds
        } else if Self.isUsableAnchor(candidate.bounds) {
            anchor = candidate.bounds
        } else {
            anchor = fallbackAnchor
        }

        let resolved = candidate.replacingAnchorBounds(anchor)
        lastSelection = resolved
        return resolved
    }

    public mutating func clear() {
        lastSelection = nil
    }

    private static func isUsableAnchor(_ bounds: CGRect) -> Bool {
        !bounds.isNull
            && !bounds.isInfinite
            && bounds.origin.x.isFinite
            && bounds.origin.y.isFinite
            && bounds.width.isFinite
            && bounds.height.isFinite
            && bounds.width > 0
            && bounds.height > 0
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
