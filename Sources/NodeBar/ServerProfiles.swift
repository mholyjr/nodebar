import Foundation

struct ServerProfile: Codable, Hashable, Identifiable {
    let id: UUID
    var displayName: String
    var framework: NodeFramework
    var workingDirectory: String
    var command: String
    var inferredCommand: Bool
    var scriptName: String?
    var originalPort: UInt16
    var preferredPort: UInt16
    var usePortEnvironment: Bool
    var observedCommand: String
    var observedPort: UInt16

    var directoryURL: URL? {
        guard !workingDirectory.isEmpty else { return nil }
        return URL(fileURLWithPath: workingDirectory)
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        framework: NodeFramework,
        workingDirectory: String,
        command: String,
        inferredCommand: Bool,
        scriptName: String?,
        originalPort: UInt16,
        preferredPort: UInt16,
        usePortEnvironment: Bool,
        observedCommand: String,
        observedPort: UInt16
    ) {
        self.id = id
        self.displayName = displayName
        self.framework = framework
        self.workingDirectory = workingDirectory
        self.command = command
        self.inferredCommand = inferredCommand
        self.scriptName = scriptName
        self.originalPort = originalPort
        self.preferredPort = preferredPort
        self.usePortEnvironment = usePortEnvironment
        self.observedCommand = observedCommand
        self.observedPort = observedPort
    }

}

struct ServerItem: Identifiable, Hashable {
    let profile: ServerProfile
    let liveServer: NodeServer?

    var id: UUID { profile.id }
    var isRunning: Bool { liveServer != nil }
    var currentPort: UInt16? { liveServer?.ports.first?.port }
    var framework: NodeFramework { liveServer?.framework ?? profile.framework }
}

enum ProfilePersistenceError: LocalizedError {
    case unreadable(Error)
    case unwritable(Error)

    var errorDescription: String? {
        switch self {
        case .unreadable(let error):
            return "NodeBar could not load saved servers: \(error.localizedDescription)"
        case .unwritable(let error):
            return "NodeBar could not save server settings: \(error.localizedDescription)"
        }
    }
}

struct ServerProfileStorage {
    let fileURL: URL
    private let fileManager = FileManager.default

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NodeBar", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    func load() throws -> [ServerProfile] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([ServerProfile].self, from: data)
        } catch {
            throw ProfilePersistenceError.unreadable(error)
        }
    }

    func save(_ profiles: [ServerProfile]) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw ProfilePersistenceError.unwritable(error)
        }
    }
}
