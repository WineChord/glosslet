import Foundation

public enum GlossletConstants {
    public static let appName = "Glosslet"
    public static let executableName = "Glosslet"
    public static let bundleIdentifier = "com.winechord.glosslet"
    public static let clientName = "glosslet"
    public static let appVersion = "0.2.4"
    public static let buildNumber = "6"

    public static let codexPathEnvironmentKey = "GLOSSLET_CODEX_PATH"
    public static let requestTimeoutSeconds: UInt64 = 20
    public static let maximumSelectionCharacters = 100_000
    public static let proactiveCompactionInputTokens = 32_000

    public static let repositoryURL = URL(
        string: "https://github.com/WineChord/glosslet"
    )!

    public static var defaultWorkspaceURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
    }
}
