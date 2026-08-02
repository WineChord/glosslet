import Foundation

/// A short, bounded retry schedule for reconnecting to the local Codex
/// runtime. The first retry is intentionally quick; later retries avoid a
/// tight loop while Codex is restarting or macOS is waking.
public struct RecoveryBackoff: Equatable, Sendable {
    public static let defaultDelays: [TimeInterval] = [
        0.35,
        0.75,
        1.5,
        3,
        6,
        12,
    ]

    public let delays: [TimeInterval]
    public private(set) var retryCount = 0

    public init(delays: [TimeInterval] = Self.defaultDelays) {
        precondition(!delays.isEmpty)
        precondition(delays.allSatisfy { $0 >= 0 })
        self.delays = delays
    }

    public mutating func nextDelay() -> TimeInterval {
        let index = min(retryCount, delays.count - 1)
        retryCount += 1
        return delays[index]
    }

    public mutating func reset() {
        retryCount = 0
    }
}
