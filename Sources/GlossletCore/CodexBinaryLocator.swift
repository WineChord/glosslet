import Foundation

public enum CodexBinaryLocator {
    public static func findBinary() -> URL? {
        findBinary(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    public static func findControlSocket() -> URL? {
        findControlSocket(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func findControlSocket(
        environment: [String: String],
        homeDirectory: URL,
        fileManager: FileManager = .default,
        socketAvailable: ((String) -> Bool)? = nil
    ) -> URL? {
        let codexHome: URL
        if let configuredHome = environment["CODEX_HOME"],
            !configuredHome.isEmpty
        {
            codexHome = URL(fileURLWithPath: configuredHome)
        } else {
            codexHome = homeDirectory.appendingPathComponent(
                ".codex",
                isDirectory: true
            )
        }
        let socket =
            codexHome
            .appendingPathComponent("app-server-control", isDirectory: true)
            .appendingPathComponent("app-server-control.sock")
        let isAvailable =
            socketAvailable?(socket.path)
            ?? {
                guard
                    let attributes = try? fileManager.attributesOfItem(
                        atPath: socket.path
                    ),
                    let type = attributes[.type] as? FileAttributeType
                else {
                    return false
                }
                return type == .typeSocket
            }()
        return isAvailable ? socket : nil
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
