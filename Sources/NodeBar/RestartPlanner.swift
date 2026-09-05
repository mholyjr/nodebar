import Foundation

struct RestartPlanner {
    private let metadataReader = PackageMetadataReader()

    func makePlan(for server: NodeServer, port: UInt16, scriptName: String? = nil) -> RestartPlan? {
        guard let workingDirectory = server.workingDirectory else { return nil }

        let package = metadataReader.read(from: workingDirectory)
        let packageFramework = package?.metadataWarning == nil ? package?.framework : nil
        let framework: NodeFramework
        if let packageFramework, packageFramework != .node {
            framework = packageFramework
        } else {
            framework = NodeFramework.from(command: server.command)
        }
        let scriptOptions = package?.metadataWarning == nil ? package?.scriptOptions ?? [] : []
        let selectedScript = chooseScript(
            requested: scriptName,
            options: scriptOptions,
            command: server.command,
            framework: framework
        )

        let suggestion: Suggestion
        if let package, package.metadataWarning == nil,
           let selectedScript,
           framework.supportsPortArgument,
           isForwardableScript(selectedScript.command, framework: framework) {
            let command = package.packageManager.command(for: selectedScript.name, port: port)
            suggestion = Suggestion(
                command: command,
                wasInferred: true,
                note: "From package.json · \(package.packageManager.executable) / \(selectedScript.name)"
            )
        } else {
            suggestion = makeCommandSuggestion(
                for: server.command,
                port: port,
                framework: framework,
                packageWarning: package?.metadataWarning
            )
        }

        return RestartPlan(
            server: server,
            requestedPort: port,
            command: suggestion.command,
            workingDirectory: package?.metadataWarning == nil ? package?.rootDirectory ?? workingDirectory : workingDirectory,
            portArgumentWasInferred: suggestion.wasInferred,
            inferenceNote: suggestion.note,
            framework: framework,
            selectedScriptName: selectedScript?.name,
            scriptOptions: scriptOptions,
            usePortEnvironment: false
        )
    }

    func commandByUpdatingKnownPort(_ command: String, port: UInt16) -> String {
        replacePortFlag(in: command, port: port)
    }

    private struct Suggestion {
        let command: String
        let wasInferred: Bool
        let note: String
    }

    private func chooseScript(
        requested: String?,
        options: [PackageScript],
        command: String,
        framework: NodeFramework
    ) -> PackageScript? {
        if let requested, let match = options.first(where: { $0.name == requested }) {
            return match
        }
        guard !options.isEmpty else { return nil }

        let lowercased = command.lowercased()
        if let token = framework.commandToken {
            if lowercased.contains("\(token) start"), let start = options.first(where: { $0.name == "start" }) {
                return start
            }
            if lowercased.contains("\(token) dev"), let dev = options.first(where: { $0.name == "dev" }) {
                return dev
            }
        }
        return options.first
    }

    private func makeCommandSuggestion(
        for originalCommand: String,
        port: UInt16,
        framework: NodeFramework,
        packageWarning: String?
    ) -> Suggestion {
        guard isShellSafe(originalCommand) else {
            return Suggestion(
                command: "",
                wasInferred: false,
                note: "The process command contains shell-sensitive text, so it was left blank. Enter and review the restart command."
            )
        }

        let tokens = originalCommand.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let tool = tokens.prefix(6).compactMap(toolName(from:)).first else {
            let note: String
            if let packageWarning {
                note = "\(packageWarning) Enter and review the command used to start this server."
            } else if framework.supportsPortArgument {
                note = "\(framework.displayName) was detected, but no package script was available. Enter and review the command used to start this server."
            } else {
                note = "NodeBar could not safely infer a restart command. Enter the command you use to start this server."
            }
            return Suggestion(command: "", wasInferred: false, note: note)
        }

        let updated = replacePortFlag(in: originalCommand, port: port)
        let note = "\(tool.capitalized) CLI detected. NodeBar prepared a suggested --port argument; review it before restarting."
        return Suggestion(command: updated, wasInferred: true, note: note)
    }

    private func toolName(from token: String) -> String? {
        let lowercased = token.lowercased()
        guard !lowercased.hasPrefix("-") else { return nil }
        let basename = URL(fileURLWithPath: lowercased).lastPathComponent
        if basename == "vite" || basename == "vite.js" { return "vite" }
        if basename == "next" || basename == "next.js" { return "next" }
        if basename == "nuxt" || basename == "nuxt.js" { return "nuxt" }
        if basename == "astro" || basename == "astro.js" { return "astro" }
        return nil
    }

    private func replacePortFlag(in command: String, port: UInt16) -> String {
        let pattern = #"(--port\s+|--port=|-p\s+)\d+"#
        guard let range = command.range(of: pattern, options: .regularExpression) else {
            return "\(command) --port \(port)"
        }
        let existing = String(command[range])
        let prefix = existing.prefix { !$0.isNumber }
        return command.replacingCharacters(in: range, with: "\(prefix)\(port)")
    }

    private func isForwardableScript(_ command: String, framework: NodeFramework) -> Bool {
        guard isShellSafe(command), let token = framework.commandToken else { return false }
        let commandTokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard commandTokens.contains(where: { toolName(from: $0) == token }) else { return false }
        let disallowed = Set(["concurrently", "npm-run-all", "run-p", "run-s"])
        return !commandTokens.contains(where: { disallowed.contains(URL(fileURLWithPath: $0.lowercased()).lastPathComponent) })
    }

    private func isShellSafe(_ command: String) -> Bool {
        guard !command.isEmpty else { return false }
        let unsafeCharacters = CharacterSet(charactersIn: "'\"`$;&|<>\\(){}[]*?!")
        return command.unicodeScalars.allSatisfy { scalar in
            !unsafeCharacters.contains(scalar) && !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}
