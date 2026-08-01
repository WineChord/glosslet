import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginController {
    enum Status: String {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
    }

    enum Failure: LocalizedError {
        case requiresApproval
        case unexpectedStatus(Status)

        var errorDescription: String? {
            switch self {
            case .requiresApproval:
                L10n.launchAtLoginApprovalRequired
            case .unexpectedStatus:
                L10n.launchAtLoginUnavailable
            }
        }
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    @discardableResult
    static func synchronize(preferredEnabled: Bool) throws -> Bool {
        switch status {
        case .enabled:
            return true
        case .requiresApproval:
            return false
        case .notRegistered, .notFound:
            guard preferredEnabled else {
                return false
            }
            try setEnabled(true)
            return true
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            switch status {
            case .enabled:
                return
            case .requiresApproval:
                throw Failure.requiresApproval
            case .notRegistered, .notFound:
                try SMAppService.mainApp.register()
            }
            guard status == .enabled else {
                if status == .requiresApproval {
                    throw Failure.requiresApproval
                }
                throw Failure.unexpectedStatus(status)
            }
        } else {
            switch status {
            case .enabled, .requiresApproval:
                try SMAppService.mainApp.unregister()
            case .notRegistered, .notFound:
                return
            }
            guard status != .enabled else {
                throw Failure.unexpectedStatus(status)
            }
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
