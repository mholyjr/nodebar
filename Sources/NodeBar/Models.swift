import Foundation

struct PortBinding: Hashable {
    let port: UInt16
    let hosts: [String]

    var displayValue: String {
        let host = hosts.first ?? "*"
        return "\(host):\(port)"
    }
}

struct ProcessIdentity: Equatable, Hashable {
    let pid: Int32
    let startTime: UInt64?
    let command: String
    let executablePath: String
    let workingDirectory: String
    let ports: [UInt16]
}

struct NodeServer: Identifiable, Hashable {
    let pid: Int32
    let command: String
    let executablePath: String
    let workingDirectory: URL?
    let ports: [PortBinding]
    let identity: ProcessIdentity

    var id: String {
        String(pid)
    }

    var projectName: String {
        if let directory = workingDirectory?.lastPathComponent, !directory.isEmpty {
            return directory
        }
        return URL(fileURLWithPath: executablePath).lastPathComponent
    }

    var portSummary: String {
        ports.map(\.displayValue).joined(separator: ", ")
    }
}

struct RestartPlan {
    let server: NodeServer
    let requestedPort: UInt16
    let command: String
    let workingDirectory: URL
    let portArgumentWasInferred: Bool
    let inferenceNote: String
    var usePortEnvironment: Bool

    var commandForLaunch: String {
        command
    }
}

enum DiscoveryError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

enum ProcessActionError: LocalizedError {
    case discoveryFailed(String)
    case staleProcess
    case portUnavailable(UInt16)
    case invalidPort
    case missingWorkingDirectory
    case emptyRestartCommand
    case signalFailed(pid: Int32, signal: String, reason: String)
    case restartLaunchFailed(String)
    case restartTimedOut(UInt16)
    case verificationFailed(UInt16)

    var errorDescription: String? {
        switch self {
        case .discoveryFailed(let message):
            return message
        case .staleProcess:
            return "The process changed before NodeBar could act on it. Refresh and try again."
        case .portUnavailable(let port):
            return "Port \(port) is already in use. Choose another port."
        case .invalidPort:
            return "Enter a port number between 1 and 65535."
        case .missingWorkingDirectory:
            return "NodeBar could not determine the server's project directory."
        case .emptyRestartCommand:
            return "Enter the command used to restart this server before continuing."
        case .signalFailed(let pid, let signal, let reason):
            return "Could not send \(signal) to PID \(pid): \(reason)"
        case .restartLaunchFailed(let reason):
            return "Could not start the restart command: \(reason)"
        case .restartTimedOut(let port):
            return "No listener appeared on port \(port) after the restart command ran. Check ~/Library/Logs/NodeBar/restarts.log for command output."
        case .verificationFailed(let port):
            return "A listener appeared on port \(port), but it could not be matched to the restarted project. Check ~/Library/Logs/NodeBar/restarts.log for command output."
        }
    }
}
