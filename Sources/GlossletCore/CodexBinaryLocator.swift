import Foundation

public enum CodexBinaryLocator {
    public static func findBinary() -> URL? {
        findBinary(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func findBinary(
        environment: [String: String],
        homeDirectory: URL,
        systemCandidates: [String] = defaultSystemCandidatePaths,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment[
            GlossletConstants.codexPathEnvironmentKey
        ], fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        return candidatePaths(
            environment: environment,
            homeDirectory: homeDirectory,
            systemCandidates: systemCandidates
        )
        .first(where: fileManager.isExecutableFile(atPath:))
        .map { URL(fileURLWithPath: $0) }
    }

    static func candidatePaths(
        environment: [String: String],
        homeDirectory: URL,
        systemCandidates: [String] = defaultSystemCandidatePaths
    ) -> [String] {
        let homeCandidates = [
            homeDirectory
                .appendingPathComponent(
                    ".codex/packages/standalone/current/bin/codex"
                )
                .path,
            homeDirectory
                .appendingPathComponent(
                    ".codex/packages/standalone/current/codex"
                )
                .path,
            homeDirectory.appendingPathComponent(".local/bin/codex").path,
        ]
        let executablePathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map {
                URL(fileURLWithPath: $0)
                    .appendingPathComponent("codex")
                    .path
            }
        return homeCandidates + executablePathCandidates + systemCandidates
    }

    private static let defaultSystemCandidatePaths = [
        "/Applications/Codex.app/Contents/Resources/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
    ]
}
