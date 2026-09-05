import Foundation

struct RestartPlanner {
    func makePlan(for server: NodeServer, port: UInt16) -> RestartPlan? {
        guard let workingDirectory = server.workingDirectory else { return nil }
        let suggestion = makeSuggestion(for: server.command, port: port)
        return RestartPlan(
            server: server,
            requestedPort: port,
            command: suggestion.command,
            workingDirectory: workingDirectory,
            portArgumentWasInferred: suggestion.wasInferred,
            inferenceNote: suggestion.note,
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

    private func makeSuggestion(for originalCommand: String, port: UInt16) -> Suggestion {
        let tokens = tokenize(originalCommand)
        guard let tool = tokens.prefix(6).compactMap(toolName(from:)).first else {
            return Suggestion(
                command: "",
                wasInferred: false,
                note: "NodeBar could not safely infer a restart command. Enter the command you use to start this server."
            )
        }
        guard isShellSafe(originalCommand) else {
            return Suggestion(
                command: "",
                wasInferred: false,
                note: "The process command contains shell-sensitive text, so it was left blank. Enter and review the restart command."
            )
        }

        let updated = replacePortFlag(in: originalCommand, port: port)
        let note: String
        switch tool {
        case "vite":
            note = "Vite CLI detected. NodeBar prepared a suggested --port argument; review it before restarting."
        case "next":
            note = "Next CLI detected. NodeBar prepared a suggested --port argument; review it before restarting."
        default:
            note = ""
        }
        return Suggestion(command: updated, wasInferred: true, note: note)
    }

    private func toolName(from token: String) -> String? {
        let lowercased = token.lowercased()
        guard !lowercased.hasPrefix("-") else { return nil }
        let basename = URL(fileURLWithPath: lowercased).lastPathComponent
        if basename == "vite" || basename == "vite.js" {
            return "vite"
        }
        if basename == "next" || basename == "next.js" {
            return "next"
        }
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

    private func isShellSafe(_ command: String) -> Bool {
        guard !command.isEmpty else { return false }
        let unsafeCharacters = CharacterSet(charactersIn: "'\"`$;&|<>\\(){}[]*?!")
        return command.unicodeScalars.allSatisfy { scalar in
            !unsafeCharacters.contains(scalar) && !CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false

        for character in command {
            if escaped {
                token.append(character)
                escaped = false
                continue
            }
            if character == "\\" && quote != "'" {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    token.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !token.isEmpty {
                    tokens.append(token)
                    token = ""
                }
            } else {
                token.append(character)
            }
        }
        if escaped { token.append("\\") }
        if !token.isEmpty { tokens.append(token) }
        return tokens
    }
}
