import Foundation
import Darwin

struct NodeProcessDiscovery {
    private struct ListenerRecord {
        let pid: Int32
        let ports: [PortBinding]
    }

    private struct ProcessFileRecord {
        var executablePath: String?
        var workingDirectory: String?
    }

    private let runner = CommandRunner()
    private let username: String

    init(username: String = NSUserName()) {
        self.username = username
    }

    func discover() throws -> [NodeServer] {
        let listeners = try listenerRecords()
        guard !listeners.isEmpty else { return [] }

        let pids = listeners.map { String($0.pid) }.joined(separator: ",")
        let processFiles = try processFileRecords(for: pids)
        let commands = try processCommands(for: pids)

        return listeners.compactMap { listener in
            guard let files = processFiles[listener.pid],
                  let executablePath = files.executablePath,
                  isNodeExecutable(executablePath),
                  let command = commands[listener.pid],
                  !command.isEmpty,
                  let workingDirectoryPath = files.workingDirectory else {
                return nil
            }

            let identity = ProcessIdentity(
                pid: listener.pid,
                startTime: processStartTime(for: listener.pid),
                command: command,
                executablePath: executablePath,
                workingDirectory: workingDirectoryPath,
                ports: listener.ports.map(\.port)
            )
            return NodeServer(
                pid: listener.pid,
                command: command,
                executablePath: executablePath,
                workingDirectory: URL(fileURLWithPath: workingDirectoryPath),
                ports: listener.ports,
                identity: identity
            )
        }
        .sorted { lhs, rhs in
            if lhs.projectName == rhs.projectName {
                return lhs.pid < rhs.pid
            }
            return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
        }
    }

    func identity(for pid: Int32) throws -> ProcessIdentity? {
        let processFiles = try processFileRecords(for: String(pid))
        let commands = try processCommands(for: String(pid))
        guard let files = processFiles[pid],
              let executablePath = files.executablePath,
              let workingDirectory = files.workingDirectory,
              let command = commands[pid],
              !command.isEmpty else {
            return nil
        }
        return ProcessIdentity(
            pid: pid,
            startTime: processStartTime(for: pid),
            command: command,
            executablePath: executablePath,
            workingDirectory: workingDirectory,
            ports: []
        )
    }

    private func listenerRecords() throws -> [ListenerRecord] {
        let output = try runner.run(
            executablePath: "/usr/sbin/lsof",
            arguments: [
                "-nP",
                "-a",
                "-u", username,
                "-iTCP",
                "-sTCP:LISTEN",
                "-Fpcfn"
            ]
        )

        if output.status != 0 {
            let error = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !error.isEmpty {
                throw DiscoveryError.commandFailed(error)
            }
            if output.standardOutput.isEmpty {
                return []
            }
        }

        guard !output.standardOutput.isEmpty else {
            return []
        }

        var records: [ListenerRecord] = []
        var currentPID: Int32?
        var currentPorts: [UInt16: Set<String>] = [:]

        for line in output.standardOutput.split(whereSeparator: \.isNewline) {
            let field = String(line)
            guard let key = field.first else { continue }
            let value = String(field.dropFirst())

            if key == "p" {
                if let pid = currentPID {
                    records.append(ListenerRecord(
                        pid: pid,
                        ports: makePortBindings(from: currentPorts)
                    ))
                }
                currentPID = Int32(value)
                currentPorts = [:]
            } else if key == "n", let endpoint = parseEndpoint(value) {
                currentPorts[endpoint.port, default: []].insert(endpoint.host)
            }
        }

        if let pid = currentPID {
            records.append(ListenerRecord(
                pid: pid,
                ports: makePortBindings(from: currentPorts)
            ))
        }

        return records.filter { !$0.ports.isEmpty }
    }

    private func processFileRecords(for pids: String) throws -> [Int32: ProcessFileRecord] {
        let output = try runner.run(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-a", "-p", pids, "-d", "cwd,txt", "-Fn"]
        )

        if output.status != 0 && output.standardOutput.isEmpty {
            let error = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !error.isEmpty {
                throw DiscoveryError.commandFailed(error)
            }
        }

        var records: [Int32: ProcessFileRecord] = [:]
        var currentPID: Int32?
        var currentFileType = ""

        for line in output.standardOutput.split(whereSeparator: \.isNewline) {
            let field = String(line)
            guard let key = field.first else { continue }
            let value = String(field.dropFirst())

            switch key {
            case "p":
                currentPID = Int32(value)
                if let pid = currentPID {
                    records[pid] = ProcessFileRecord()
                }
            case "f":
                currentFileType = value
            case "n":
                guard let pid = currentPID else { continue }
                guard var record = records[pid] else { continue }
                if currentFileType == "cwd", record.workingDirectory == nil {
                    record.workingDirectory = value
                } else if currentFileType == "txt", record.executablePath == nil {
                    record.executablePath = value
                }
                records[pid] = record
            default:
                continue
            }
        }

        return records
    }

    private func processCommands(for pids: String) throws -> [Int32: String] {
        let output = try runner.run(
            executablePath: "/bin/ps",
            arguments: ["-ww", "-p", pids, "-o", "pid=,command="]
        )

        if output.status != 0 && output.standardOutput.isEmpty {
            let error = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if !error.isEmpty {
                throw DiscoveryError.commandFailed(error)
            }
        }

        var commands: [Int32: String] = [:]
        for line in output.standardOutput.split(whereSeparator: \.isNewline) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = text.firstIndex(where: { $0.isWhitespace }) else { continue }
            let pidText = String(text[..<separator])
            let command = String(text[text.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(pidText), !command.isEmpty else { continue }
            commands[pid] = command
        }
        return commands
    }

    private func isNodeExecutable(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return name == "node" || name == "nodejs"
    }

    private func processStartTime(for pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, expectedSize)
        }
        guard result == expectedSize else { return nil }
        return (info.pbi_start_tvsec * 1_000_000) + info.pbi_start_tvusec
    }

    private func makePortBindings(from ports: [UInt16: Set<String>]) -> [PortBinding] {
        ports.keys.sorted().map { port in
            PortBinding(port: port, hosts: ports[port, default: []].sorted())
        }
    }

    private func parseEndpoint(_ value: String) -> (host: String, port: UInt16)? {
        if let closeBracket = value.lastIndex(of: "]"),
           closeBracket < value.endIndex,
           value.index(after: closeBracket) < value.endIndex,
           value[value.index(after: closeBracket)] == ":" {
            let host = String(value[value.index(after: value.startIndex)..<closeBracket])
            let portStart = value.index(closeBracket, offsetBy: 2)
            guard let port = UInt16(value[portStart...]) else { return nil }
            return (host.isEmpty ? "*" : host, port)
        }

        guard let colon = value.lastIndex(of: ":") else { return nil }
        let host = String(value[..<colon])
        let portStart = value.index(after: colon)
        guard let port = UInt16(value[portStart...]) else { return nil }
        return (host.isEmpty ? "*" : host, port)
    }
}
