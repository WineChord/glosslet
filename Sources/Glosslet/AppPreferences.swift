import Combine
import Foundation
import GlossletCore

enum ThreadMode: String, CaseIterable, Identifiable {
    case reuseFixed
    case newPerExplanation

    var id: String { rawValue }
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let selectionEnabled = "selectionEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let threadMode = "threadMode"
        static let modelPolicy = "modelPolicy"
        static let customModelID = "customModelID"
        static let customEffort = "customEffort"
        static let explanationLanguage = "explanationLanguage"
        static let fixedThreadID = "fixedThreadID"
        static let completedOnboarding = "completedOnboarding"
    }

    private let defaults: UserDefaults

    @Published var selectionEnabled: Bool {
        didSet { defaults.set(selectionEnabled, forKey: Key.selectionEnabled) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published var threadMode: ThreadMode {
        didSet { defaults.set(threadMode.rawValue, forKey: Key.threadMode) }
    }

    @Published var modelPolicy: ModelPolicy {
        didSet { defaults.set(modelPolicy.rawValue, forKey: Key.modelPolicy) }
    }

    @Published var customModelID: String? {
        didSet { defaults.set(customModelID, forKey: Key.customModelID) }
    }

    @Published var customEffort: String? {
        didSet { defaults.set(customEffort, forKey: Key.customEffort) }
    }

    @Published var explanationLanguage: ExplanationLanguage {
        didSet {
            defaults.set(
                explanationLanguage.rawValue,
                forKey: Key.explanationLanguage
            )
        }
    }

    @Published private(set) var fixedThreadID: String? {
        didSet { defaults.set(fixedThreadID, forKey: Key.fixedThreadID) }
    }

    @Published var completedOnboarding: Bool {
        didSet {
            defaults.set(
                completedOnboarding,
                forKey: Key.completedOnboarding
            )
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.selectionEnabled: true,
            Key.launchAtLogin: false,
            Key.threadMode: ThreadMode.reuseFixed.rawValue,
            Key.modelPolicy: ModelPolicy.latestLowest.rawValue,
            Key.explanationLanguage: ExplanationLanguage.automatic.rawValue,
            Key.completedOnboarding: false,
        ])

        selectionEnabled = defaults.bool(forKey: Key.selectionEnabled)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        threadMode =
            ThreadMode(
                rawValue: defaults.string(forKey: Key.threadMode) ?? ""
            ) ?? .reuseFixed
        modelPolicy =
            ModelPolicy(
                rawValue: defaults.string(forKey: Key.modelPolicy) ?? ""
            ) ?? .latestLowest
        customModelID = defaults.string(forKey: Key.customModelID)
        customEffort = defaults.string(forKey: Key.customEffort)
        explanationLanguage =
            ExplanationLanguage(
                rawValue: defaults.string(
                    forKey: Key.explanationLanguage
                ) ?? ""
            ) ?? .automatic
        fixedThreadID = defaults.string(forKey: Key.fixedThreadID)
        completedOnboarding = defaults.bool(
            forKey: Key.completedOnboarding
        )
    }

    func useFixedThread(_ identifier: String) {
        fixedThreadID = identifier
    }

    func resetFixedThread() {
        fixedThreadID = nil
    }
}
