import AppKit
import Foundation

private struct ListItem: Encodable {
    let pid: Int32
    let ports: [UInt16]
    let project: String
    let workingDirectory: String?
}

if CommandLine.arguments.dropFirst().contains("--list") {
    do {
        let servers = try NodeProcessDiscovery().discover()
        let items = servers.map { server in
            ListItem(
                pid: server.pid,
                ports: server.ports.map(\.port),
                project: server.projectName,
                workingDirectory: server.workingDirectory?.path
            )
        }
        let data = try JSONEncoder().encode(items)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("NodeBar discovery failed: \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
