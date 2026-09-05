import Foundation

enum NodeFramework: String, Codable, CaseIterable {
    case node
    case next
    case vite
    case nuxt
    case astro

    var displayName: String {
        switch self {
        case .node: return "Node"
        case .next: return "Next"
        case .vite: return "Vite"
        case .nuxt: return "Nuxt"
        case .astro: return "Astro"
        }
    }

    var commandToken: String? {
        switch self {
        case .node: return nil
        case .next: return "next"
        case .vite: return "vite"
        case .nuxt: return "nuxt"
        case .astro: return "astro"
        }
    }

    var supportsPortArgument: Bool {
        self != .node
    }

    static func from(metadata: PackageMetadata) -> NodeFramework {
        let packages = Set((Array(metadata.dependencies.keys) + Array(metadata.devDependencies.keys)).map { $0.lowercased() })
        if packages.contains("next") { return .next }
        if packages.contains("nuxt") { return .nuxt }
        if packages.contains("astro") { return .astro }
        if packages.contains("vite") { return .vite }
        return .node
    }

    static func from(command: String) -> NodeFramework {
        let lowercased = command.lowercased()
        let tokens = lowercased.split(whereSeparator: \.isWhitespace).map(String.init)
        if lowercased.contains("next-server") || tokens.contains(where: { commandBasename($0, is: "next") }) {
            return .next
        }
        if tokens.contains(where: { commandBasename($0, is: "vite") }) {
            return .vite
        }
        if tokens.contains(where: { commandBasename($0, is: "nuxt") }) {
            return .nuxt
        }
        if tokens.contains(where: { commandBasename($0, is: "astro") }) {
            return .astro
        }
        return .node
    }

    private static func commandBasename(_ token: String, is name: String) -> Bool {
        let basename = URL(fileURLWithPath: token).lastPathComponent
        return basename == name || basename == "\(name).js"
    }
}

enum PackageManager: String, Codable {
    case npm
    case pnpm
    case yarn
    case bun

    var executable: String { rawValue }

    func command(for script: String, port: UInt16) -> String {
        let quotedScript = Self.shellQuote(script)
        let separator = self == .npm ? " --" : ""
        return "\(executable) run \(quotedScript)\(separator) --port \(port)"
    }

    private static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-:"))
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ safe.contains($0) }) else {
            return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return value
    }
}

struct PackageMetadata: Codable {
    let name: String?
    let scripts: [String: String]
    let dependencies: [String: String]
    let devDependencies: [String: String]
    let packageManager: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case scripts
        case dependencies
        case devDependencies
        case packageManager
    }

    init(
        name: String? = nil,
        scripts: [String: String] = [:],
        dependencies: [String: String] = [:],
        devDependencies: [String: String] = [:],
        packageManager: String? = nil
    ) {
        self.name = name
        self.scripts = scripts
        self.dependencies = dependencies
        self.devDependencies = devDependencies
        self.packageManager = packageManager
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        scripts = try container.decodeIfPresent([String: String].self, forKey: .scripts) ?? [:]
        dependencies = try container.decodeIfPresent([String: String].self, forKey: .dependencies) ?? [:]
        devDependencies = try container.decodeIfPresent([String: String].self, forKey: .devDependencies) ?? [:]
        packageManager = try container.decodeIfPresent(String.self, forKey: .packageManager)
    }
}

struct PackageScript: Hashable {
    let name: String
    let command: String
}

struct PackageProjectInfo {
    let rootDirectory: URL
    let metadata: PackageMetadata
    let packageManager: PackageManager
    let framework: NodeFramework
    let scriptOptions: [PackageScript]
    let metadataWarning: String?
}

struct PackageMetadataReader {
    private static let maximumAncestorDepth = 12
    private let fileManager = FileManager.default

    func read(from directory: URL) -> PackageProjectInfo? {
        let directories = ancestorDirectories(from: directory)
        var loaded: [(URL, PackageMetadata)] = []
        for candidate in directories {
            let packageURL = candidate.appendingPathComponent("package.json")
            guard fileManager.fileExists(atPath: packageURL.path) else { continue }
            guard let metadata = loadMetadata(at: candidate) else {
                return PackageProjectInfo(
                    rootDirectory: candidate,
                    metadata: PackageMetadata(),
                    packageManager: detectPackageManager(directories: directories, metadata: loaded),
                    framework: .node,
                    scriptOptions: [],
                    metadataWarning: "NodeBar found a package.json but could not read it."
                )
            }
            loaded.append((candidate, metadata))
            break
        }
        guard let (rootDirectory, metadata) = loaded.first else { return nil }

        let packageManager = detectPackageManager(directories: directories, metadata: loaded)
        let framework = NodeFramework.from(metadata: metadata)
        let scriptOptions = candidateScripts(in: metadata, for: framework)
        return PackageProjectInfo(
            rootDirectory: rootDirectory,
            metadata: metadata,
            packageManager: packageManager,
            framework: framework,
            scriptOptions: scriptOptions,
            metadataWarning: nil
        )
    }

    private func loadMetadata(at directory: URL) -> PackageMetadata? {
        let packageURL = directory.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageURL) else { return nil }
        return try? JSONDecoder().decode(PackageMetadata.self, from: data)
    }

    private func ancestorDirectories(from directory: URL) -> [URL] {
        var result: [URL] = []
        var current = directory.standardizedFileURL
        for _ in 0..<Self.maximumAncestorDepth {
            result.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return result
    }

    private func detectPackageManager(
        directories: [URL],
        metadata: [(URL, PackageMetadata)]
    ) -> PackageManager {
        for (_, package) in metadata {
            if let manager = parsePackageManager(package.packageManager) {
                return manager
            }
        }

        for directory in directories {
            if let ancestor = loadMetadata(at: directory),
               let manager = parsePackageManager(ancestor.packageManager) {
                return manager
            }
        }

        let lockfiles: [(String, PackageManager)] = [
            ("pnpm-lock.yaml", .pnpm),
            ("package-lock.json", .npm),
            ("yarn.lock", .yarn),
            ("bun.lockb", .bun),
            ("bun.lock", .bun)
        ]
        for directory in directories {
            for (name, manager) in lockfiles where fileManager.fileExists(atPath: directory.appendingPathComponent(name).path) {
                return manager
            }
        }
        return .npm
    }

    private func parsePackageManager(_ value: String?) -> PackageManager? {
        guard let value else { return nil }
        let name = value.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? value
        return PackageManager(rawValue: name.lowercased())
    }

    private func candidateScripts(in metadata: PackageMetadata, for framework: NodeFramework) -> [PackageScript] {
        guard let token = framework.commandToken else { return [] }
        let preferredNames = ["dev", "start", "preview"]
        let preferred: [PackageScript] = preferredNames.compactMap { name -> PackageScript? in
            guard let command = metadata.scripts[name], containsTool(command, named: token) else { return nil }
            return PackageScript(name: name, command: command)
        }
        let reservedNames = Set(["build", "test", "lint", "format", "typecheck", "check", "prepare", "postinstall", "prepublishOnly"])
        let custom = metadata.scripts.keys
            .filter { name in
                !preferredNames.contains(name) && !reservedNames.contains(name)
                    && (name.hasPrefix("dev") || name.hasPrefix("start") || name.hasPrefix("serve") || name.hasPrefix("preview"))
            }
            .sorted()
            .compactMap { name -> PackageScript? in
                guard let command = metadata.scripts[name], containsTool(command, named: token) else { return nil }
                return PackageScript(name: name, command: command)
            }
        return preferred + custom
    }

    private func containsTool(_ command: String, named name: String) -> Bool {
        command.split(whereSeparator: \.isWhitespace).contains { token in
            let basename = URL(fileURLWithPath: String(token).lowercased()).lastPathComponent
            return basename == name || basename == "\(name).js"
        }
    }
}
