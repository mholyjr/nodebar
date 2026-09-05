import Foundation

struct CommandOutput {
    let standardOutput: String
    let standardError: String
    let status: Int32
}

enum CommandRunnerError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        }
    }
}

struct CommandRunner {
    func run(
        executablePath: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed(error.localizedDescription)
        }

        // Read before waiting so a verbose command cannot fill its pipe and deadlock.
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let outputText = String(decoding: output, as: UTF8.self)
        return CommandOutput(
            standardOutput: outputText,
            standardError: process.terminationStatus == 0 ? "" : outputText,
            status: process.terminationStatus
        )
    }
}
