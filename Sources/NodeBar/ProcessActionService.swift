import Foundation
import Darwin

enum StopOutcome {
    case stopped
    case needsForceKill
}

final class ProcessActionService {
    private let discovery: NodeProcessDiscovery
    private let runner = CommandRunner()

    init(discovery: NodeProcessDiscovery) {
        self.discovery = discovery
    }

    func stop(
        server: NodeServer,
        completion: @escaping (Result<StopOutcome, ProcessActionError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let currentIdentity: ProcessIdentity
                if let current = try self.discovery.discover().first(where: { $0.pid == server.pid }) {
                    currentIdentity = current.identity
                } else if let current = try self.discovery.identity(for: server.pid) {
                    currentIdentity = current
                } else {
                    self.finish(completion, with: .success(.stopped))
                    return
                }
                guard self.matches(server.identity, currentIdentity, includePorts: false) else {
                    self.finish(completion, with: .failure(.staleProcess))
                    return
                }

                try self.send(signal: SIGTERM, to: server.pid, name: "SIGTERM")
                if self.waitUntilGone(pid: server.pid, timeout: 3.0) {
                    self.finish(completion, with: .success(.stopped))
                } else {
                    self.finish(completion, with: .success(.needsForceKill))
                }
            } catch let error as ProcessActionError {
                self.finish(completion, with: .failure(error))
            } catch {
                self.finish(completion, with: .failure(.discoveryFailed(error.localizedDescription)))
            }
        }
    }

    func forceStop(
        server: NodeServer,
        completion: @escaping (Result<StopOutcome, ProcessActionError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let current = try self.discovery.identity(for: server.pid) else {
                    self.finish(completion, with: .success(.stopped))
                    return
                }
                guard self.matches(server.identity, current, includePorts: false) else {
                    self.finish(completion, with: .failure(.staleProcess))
                    return
                }
                try self.send(signal: SIGKILL, to: server.pid, name: "SIGKILL")
                if self.waitUntilGone(pid: server.pid, timeout: 2.0) {
                    self.finish(completion, with: .success(.stopped))
                } else {
                    self.finish(completion, with: .failure(.signalFailed(
                        pid: server.pid,
                        signal: "SIGKILL",
                        reason: "the process is still alive"
                    )))
                }
            } catch let error as ProcessActionError {
                self.finish(completion, with: .failure(error))
            } catch {
                self.finish(completion, with: .failure(.discoveryFailed(error.localizedDescription)))
            }
        }
    }

    func restart(
        plan: RestartPlan,
        completion: @escaping (Result<StopOutcome, ProcessActionError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let server = plan.server else {
                    throw ProcessActionError.staleProcess
                }
                try self.validateCommand(plan.command)
                try self.validatePort(plan.requestedPort, excluding: server.pid)
                try self.validateWorkingDirectory(plan.workingDirectory)
                guard let current = try self.discovery.discover().first(where: { $0.pid == server.pid }) else {
                    throw ProcessActionError.staleProcess
                }
                guard self.matches(server.identity, current.identity, includePorts: true) else {
                    throw ProcessActionError.staleProcess
                }

                try self.send(signal: SIGTERM, to: server.pid, name: "SIGTERM")
                guard self.waitUntilGone(pid: server.pid, timeout: 3.0) else {
                    self.finish(completion, with: .success(.needsForceKill))
                    return
                }

                do {
                    try self.launch(plan: plan)
                } catch let error as ProcessActionError {
                    throw error
                } catch {
                    throw ProcessActionError.restartLaunchFailed(error.localizedDescription)
                }

                _ = try self.verify(plan: plan)
                self.finish(completion, with: .success(.stopped))
            } catch let error as ProcessActionError {
                self.finish(completion, with: .failure(error))
            } catch {
                self.finish(completion, with: .failure(.discoveryFailed(error.localizedDescription)))
            }
        }
    }

    func forceKillAndRestart(
        plan: RestartPlan,
        completion: @escaping (Result<StopOutcome, ProcessActionError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let server = plan.server else {
                    throw ProcessActionError.staleProcess
                }
                try self.validateCommand(plan.command)
                try self.validatePort(plan.requestedPort, excluding: server.pid)
                try self.validateWorkingDirectory(plan.workingDirectory)
                guard let current = try self.discovery.identity(for: server.pid) else {
                    throw ProcessActionError.staleProcess
                }
                guard self.matches(server.identity, current, includePorts: false) else {
                    throw ProcessActionError.staleProcess
                }
                try self.send(signal: SIGKILL, to: server.pid, name: "SIGKILL")
                guard self.waitUntilGone(pid: server.pid, timeout: 2.0) else {
                    throw ProcessActionError.signalFailed(
                        pid: server.pid,
                        signal: "SIGKILL",
                        reason: "the process is still alive"
                    )
                }

                try self.launch(plan: plan)
                _ = try self.verify(plan: plan)
                self.finish(completion, with: .success(.stopped))
            } catch let error as ProcessActionError {
                self.finish(completion, with: .failure(error))
            } catch {
                self.finish(completion, with: .failure(.discoveryFailed(error.localizedDescription)))
            }
        }
    }

    func start(
        plan: RestartPlan,
        completion: @escaping (Result<NodeServer, ProcessActionError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.validateCommand(plan.command)
                try self.validatePort(plan.requestedPort, excluding: 0)
                try self.validateWorkingDirectory(plan.workingDirectory)
                try self.launch(plan: plan)
                let server = try self.verify(plan: plan)
                self.finish(completion, with: .success(server))
            } catch let error as ProcessActionError {
                self.finish(completion, with: .failure(error))
            } catch {
                self.finish(completion, with: .failure(.discoveryFailed(error.localizedDescription)))
            }
        }
    }

    private func validatePort(_ port: UInt16, excluding pid: Int32) throws {
        guard port > 0 else { throw ProcessActionError.invalidPort }
        let output = try runner.run(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpn"]
        )
        if !output.standardError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProcessActionError.discoveryFailed(output.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        for line in output.standardOutput.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.first == "p", let foundPID = Int32(text.dropFirst()) else { continue }
            if foundPID != pid {
                throw ProcessActionError.portUnavailable(port)
            }
        }
    }

    private func validateCommand(_ command: String) throws {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProcessActionError.emptyRestartCommand
        }
    }

    private func validateWorkingDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProcessActionError.missingWorkingDirectory
        }
    }

    private func launch(plan: RestartPlan) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", plan.commandForLaunch]
        process.currentDirectoryURL = plan.workingDirectory
        if plan.usePortEnvironment {
            var environment = ProcessInfo.processInfo.environment
            environment["PORT"] = String(plan.requestedPort)
            process.environment = environment
        }
        let logDirectory = RestartLog.url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: RestartLog.url.path) {
                FileManager.default.createFile(atPath: RestartLog.url.path, contents: nil)
            }
            let logHandle = try FileHandle(forWritingTo: RestartLog.url)
            logHandle.seekToEndOfFile()
            process.standardOutput = logHandle
            process.standardError = logHandle
            process.terminationHandler = { _ in
                logHandle.closeFile()
            }
        } catch {
            throw ProcessActionError.restartLaunchFailed(error.localizedDescription)
        }
        do {
            try process.run()
        } catch {
            throw ProcessActionError.restartLaunchFailed(error.localizedDescription)
        }
    }

    private func verify(plan: RestartPlan) throws -> NodeServer {
        var sawPort = false
        for _ in 0..<32 {
            let servers: [NodeServer]
            do {
                servers = try discovery.discover()
            } catch {
                throw ProcessActionError.discoveryFailed(error.localizedDescription)
            }
            let listeners = servers.filter { server in
                server.ports.contains { $0.port == plan.requestedPort }
            }
            sawPort = sawPort || !listeners.isEmpty
            if let match = listeners.first(where: { $0.workingDirectory?.standardizedFileURL == plan.workingDirectory.standardizedFileURL }) {
                return match
            }
            usleep(250_000)
        }
        throw sawPort ? ProcessActionError.verificationFailed(plan.requestedPort) : ProcessActionError.restartTimedOut(plan.requestedPort)
    }

    private func send(signal: Int32, to pid: Int32, name: String) throws {
        guard kill(pid, signal) == 0 else {
            if errno == ESRCH { return }
            let reason = String(cString: strerror(errno))
            throw ProcessActionError.signalFailed(pid: pid, signal: name, reason: reason)
        }
    }

    private func waitUntilGone(pid: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if kill(pid, 0) != 0 && errno == ESRCH {
                return true
            }
            usleep(100_000)
        } while Date() < deadline
        return kill(pid, 0) != 0 && errno == ESRCH
    }

    private func matches(_ expected: ProcessIdentity, _ current: ProcessIdentity, includePorts: Bool) -> Bool {
        guard expected.pid == current.pid,
              let expectedStartTime = expected.startTime,
              let currentStartTime = current.startTime,
              expectedStartTime == currentStartTime,
              expected.executablePath == current.executablePath,
              expected.workingDirectory == current.workingDirectory,
              expected.command == current.command else {
            return false
        }
        return !includePorts || expected.ports == current.ports
    }

    private func finish<T>(
        _ completion: @escaping (Result<T, ProcessActionError>) -> Void,
        with result: Result<T, ProcessActionError>
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

enum RestartLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/NodeBar/restarts.log")
}
