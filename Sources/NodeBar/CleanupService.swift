import AppKit
import Foundation

enum CleanupCandidateKind: String, CaseIterable, Hashable {
    case worktree
    case worktreePrune = "worktree-prune"
    case nodeModules = "node-modules"
    case npx
    case npm
    case pnpmCache = "pnpm-cache"
    case yarn
    case playwright
    case typescript
    case nodeGyp = "node-gyp"
    case dotslash
    case bun
    case puppeteer
    case cypress
    case turbo
    case corepack
    case pnpmStore = "pnpm-store"

    var displayName: String {
        switch self {
        case .worktree: return "Linked worktree"
        case .worktreePrune: return "Stale worktree metadata"
        case .nodeModules: return "Project node_modules"
        case .npx: return "npx installation"
        case .npm: return "npm content cache"
        case .pnpmCache: return "pnpm cache"
        case .yarn: return "Yarn cache"
        case .playwright: return "Playwright browser cache"
        case .typescript: return "TypeScript cache"
        case .nodeGyp: return "node-gyp cache"
        case .dotslash: return "Dotslash cache"
        case .bun: return "Bun cache"
        case .puppeteer: return "Puppeteer cache"
        case .cypress: return "Cypress cache"
        case .turbo: return "Turbo cache"
        case .corepack: return "Corepack cache"
        case .pnpmStore: return "pnpm store"
        }
    }

    var isCache: Bool {
        switch self {
        case .worktree, .worktreePrune, .nodeModules: return false
        default: return true
        }
    }
}

struct CleanupCandidate: Identifiable, Hashable {
    let key: String
    let kind: CleanupCandidateKind
    let label: String
    let sizeKB: Int64
    let path: String
    let itemCount: Int
    let activityEpoch: Int64
    let activityDate: String
    let ageDays: Int
    let repositoryPath: String?

    var id: String { key }

    var category: String { kind.displayName }
}

struct CleanupProtectedFinding: Hashable {
    let label: String
    let reason: String
}

struct CleanupAudit {
    let candidates: [CleanupCandidate]
    let protectedFindings: [CleanupProtectedFinding]
    let totalUpperBoundKB: Int64
    let scannedAt: Date
}

enum CleanupResultStatus: String, Hashable {
    case succeeded
    case skipped
    case failed
}

struct CleanupResult: Hashable {
    let key: String
    let status: CleanupResultStatus
    let label: String
    let path: String
    let detail: String
}

struct CleanupRun {
    let results: [CleanupResult]
    let selectedCount: Int
    let succeededCount: Int
    let skippedCount: Int
    let failedCount: Int
}

enum CleanupServiceError: LocalizedError {
    case missingScript
    case invalidDays
    case launchFailed(String)
    case processFailed(Int32, String)
    case cancelled
    case invalidProtocol(String)

    var errorDescription: String? {
        switch self {
        case .missingScript:
            return "The bundled agent-junk-clean script is unavailable. Rebuild NodeBar to restore it."
        case .invalidDays:
            return "Choose an age threshold between 1 and 365000 days."
        case .launchFailed(let message):
            return "NodeBar could not start the cleanup audit: \(message)"
        case .processFailed(let status, let message):
            if message.isEmpty {
                return "The cleanup audit exited with status \(status)."
            }
            return "The cleanup audit exited with status \(status): \(message)"
        case .cancelled:
            return "The cleanup operation was cancelled. Re-scan before retrying."
        case .invalidProtocol(let message):
            return "NodeBar received an invalid cleanup response: \(message)"
        }
    }
}

final class CleanupService {
    typealias ProgressHandler = (String) -> Void

    private struct ProcessResult {
        let stdoutLines: [String]
        let stderr: String
        let status: Int32
        let cancelled: Bool
    }

    private final class LineCollector {
        private let lock = NSLock()
        private var lines: [String] = []

        func append(_ line: String) {
            lock.lock()
            lines.append(line)
            lock.unlock()
        }

        func snapshot() -> [String] {
            lock.lock()
            let copy = lines
            lock.unlock()
            return copy
        }
    }

    private let scriptURL: URL?
    private let processLock = NSLock()
    private var activeProcess: Process?
    private var cancellationRequested = false

    init() {
        scriptURL = Self.findBundledScript()
    }

    init(scriptURL: URL) {
        self.scriptURL = scriptURL
    }

    func scan(
        olderThanDays: Int,
        progress: @escaping ProgressHandler,
        completion: @escaping (Result<CleanupAudit, CleanupServiceError>) -> Void
    ) {
        guard (1...365000).contains(olderThanDays) else {
            completion(.failure(.invalidDays))
            return
        }
        run(arguments: ["--machine-scan", "--older-than", String(olderThanDays)], progress: progress) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let processResult):
                guard !processResult.cancelled else {
                    completion(.failure(.cancelled))
                    return
                }
                guard processResult.status == 0 else {
                    completion(.failure(.processFailed(processResult.status, Self.errorTail(processResult.stderr))))
                    return
                }
                do {
                    completion(.success(try Self.parseAudit(processResult.stdoutLines)))
                } catch let error as CleanupServiceError {
                    completion(.failure(error))
                } catch {
                    completion(.failure(.invalidProtocol(error.localizedDescription)))
                }
            }
        }
    }

    func clean(
        keys: [String],
        olderThanDays: Int,
        progress: @escaping ProgressHandler,
        completion: @escaping (Result<CleanupRun, CleanupServiceError>) -> Void
    ) {
        guard !keys.isEmpty else {
            completion(.failure(.invalidProtocol("no candidate was selected")))
            return
        }
        guard Set(keys).count == keys.count else {
            completion(.failure(.invalidProtocol("duplicate candidate selection")))
            return
        }
        guard (1...365000).contains(olderThanDays) else {
            completion(.failure(.invalidDays))
            return
        }
        let arguments = ["--machine-apply"] + keys + ["--older-than", String(olderThanDays)]
        run(arguments: arguments, progress: progress) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let processResult):
                guard !processResult.cancelled else {
                    completion(.failure(.cancelled))
                    return
                }
                guard processResult.status == 0 || processResult.status == 1 else {
                    completion(.failure(.processFailed(processResult.status, Self.errorTail(processResult.stderr))))
                    return
                }
                do {
                    let run = try Self.parseRun(processResult.stdoutLines, expectedKeys: Set(keys))
                    if processResult.status == 1 && run.failedCount == 0 {
                        completion(.failure(.processFailed(processResult.status, Self.errorTail(processResult.stderr))))
                        return
                    }
                    completion(.success(run))
                } catch let error as CleanupServiceError {
                    completion(.failure(error))
                } catch {
                    completion(.failure(.invalidProtocol(error.localizedDescription)))
                }
            }
        }
    }

    func cancel() {
        processLock.lock()
        cancellationRequested = true
        let process = activeProcess
        processLock.unlock()
        process?.terminate()
    }

    private func run(
        arguments: [String],
        progress: @escaping ProgressHandler,
        completion: @escaping (Result<ProcessResult, CleanupServiceError>) -> Void
    ) {
        guard let scriptURL else {
            completion(.failure(.missingScript))
            return
        }

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            completion(.failure(.launchFailed(error.localizedDescription)))
            return
        }

        processLock.lock()
        activeProcess = process
        cancellationRequested = false
        processLock.unlock()

        let stdout = LineCollector()
        let stderr = LineCollector()
        let readers = DispatchGroup()
        Self.streamLines(from: stdoutPipe.fileHandleForReading, collector: stdout, progress: nil, group: readers)
        Self.streamLines(from: stderrPipe.fileHandleForReading, collector: stderr, progress: progress, group: readers)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            process.waitUntilExit()
            readers.wait()
            let wasCancelled = self?.finish(process: process) ?? false
            let processResult = ProcessResult(
                stdoutLines: stdout.snapshot(),
                stderr: stderr.snapshot().joined(separator: "\n"),
                status: process.terminationStatus,
                cancelled: wasCancelled
            )
            DispatchQueue.main.async {
                completion(.success(processResult))
            }
        }
    }

    private func finish(process: Process) -> Bool {
        processLock.lock()
        let wasCancelled = cancellationRequested && activeProcess === process
        if activeProcess === process {
            activeProcess = nil
            cancellationRequested = false
        }
        processLock.unlock()
        return wasCancelled
    }

    private static func streamLines(
        from handle: FileHandle,
        collector: LineCollector,
        progress: ProgressHandler?,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[..<newline]
                    buffer.removeSubrange(...newline)
                    let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .newlines)
                    collector.append(line)
                    if let progress {
                        DispatchQueue.main.async {
                            progress(line)
                        }
                    }
                }
            }
            if !buffer.isEmpty {
                let line = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .newlines)
                collector.append(line)
                if let progress {
                    DispatchQueue.main.async {
                        progress(line)
                    }
                }
            }
            group.leave()
        }
    }

    private static func findBundledScript() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let scriptURL = resourceURL.appendingPathComponent("agent-junk-clean")
        return FileManager.default.isExecutableFile(atPath: scriptURL.path) ? scriptURL : nil
    }

    private static func errorTail(_ stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1000 else { return trimmed }
        return String(trimmed.suffix(1000))
    }

    private static func parseAudit(_ lines: [String]) throws -> CleanupAudit {
        guard lines.first == "HEADER\tAGENT_JUNK_CLEAN_V1" else {
            throw CleanupServiceError.invalidProtocol("missing machine audit header")
        }

        var candidates: [CleanupCandidate] = []
        var protectedFindings: [CleanupProtectedFinding] = []
        var summary: (Int, Int, Int64)?
        for line in lines.dropFirst() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let record = fields.first else { continue }
            switch record {
            case "CANDIDATE":
                guard fields.count == 13 else { throw invalidFieldCount(record, fields.count) }
                let kind = try parseKind(try decode(fields[2], field: "candidate kind"))
                let key = try parseKey(fields[1])
                let size = try parseNonNegativeInt64(fields[4], field: "candidate size")
                let count = try parseNonNegativeInt(fields[6], field: "candidate count")
                let activity = try parseNonNegativeInt64(fields[7], field: "activity epoch")
                let age = try parseNonNegativeInt(fields[9], field: "candidate age")
                candidates.append(CleanupCandidate(
                    key: key,
                    kind: kind,
                    label: try decode(fields[3], field: "candidate label"),
                    sizeKB: size,
                    path: try decode(fields[5], field: "candidate path"),
                    itemCount: count,
                    activityEpoch: activity,
                    activityDate: try decode(fields[8], field: "activity date"),
                    ageDays: age,
                    repositoryPath: try optionalDecode(fields[10], field: "repository path")
                ))
            case "PROTECTED":
                guard fields.count == 3 else { throw invalidFieldCount(record, fields.count) }
                protectedFindings.append(CleanupProtectedFinding(
                    label: try decode(fields[1], field: "protected label"),
                    reason: try decode(fields[2], field: "protected reason")
                ))
            case "SUMMARY":
                guard fields.count == 4, summary == nil else { throw CleanupServiceError.invalidProtocol("invalid audit summary") }
                let candidateCount = try parseNonNegativeInt(fields[1], field: "summary candidates")
                let protectedCount = try parseNonNegativeInt(fields[2], field: "summary protected findings")
                let total = try parseNonNegativeInt64(fields[3], field: "summary size")
                summary = (candidateCount, protectedCount, total)
            default:
                throw CleanupServiceError.invalidProtocol("unexpected audit record \(record)")
            }
        }

        guard let summary else { throw CleanupServiceError.invalidProtocol("missing audit summary") }
        guard summary.0 == candidates.count, summary.1 == protectedFindings.count else {
            throw CleanupServiceError.invalidProtocol("audit summary counts do not match records")
        }
        return CleanupAudit(
            candidates: candidates,
            protectedFindings: protectedFindings,
            totalUpperBoundKB: summary.2,
            scannedAt: Date()
        )
    }

    private static func parseRun(_ lines: [String], expectedKeys: Set<String>) throws -> CleanupRun {
        guard lines.first == "HEADER\tAGENT_JUNK_CLEAN_V1" else {
            throw CleanupServiceError.invalidProtocol("missing machine apply header")
        }

        var results: [CleanupResult] = []
        var summary: (Int, Int, Int, Int)?
        for line in lines.dropFirst() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let record = fields.first else { continue }
            switch record {
            case "RESULT":
                guard fields.count == 6 else { throw invalidFieldCount(record, fields.count) }
                guard let status = CleanupResultStatus(rawValue: fields[2]) else {
                    throw CleanupServiceError.invalidProtocol("unknown cleanup result status")
                }
                results.append(CleanupResult(
                    key: try parseKey(fields[1]),
                    status: status,
                    label: try decode(fields[3], field: "result label"),
                    path: try decode(fields[4], field: "result path"),
                    detail: try decode(fields[5], field: "result detail")
                ))
            case "SUMMARY":
                guard fields.count == 5, summary == nil else { throw CleanupServiceError.invalidProtocol("invalid apply summary") }
                summary = (
                    try parseNonNegativeInt(fields[1], field: "selected count"),
                    try parseNonNegativeInt(fields[2], field: "succeeded count"),
                    try parseNonNegativeInt(fields[3], field: "skipped count"),
                    try parseNonNegativeInt(fields[4], field: "failed count")
                )
            default:
                throw CleanupServiceError.invalidProtocol("unexpected apply record \(record)")
            }
        }
        guard let summary else { throw CleanupServiceError.invalidProtocol("missing apply summary") }
        guard summary.0 == expectedKeys.count else {
            throw CleanupServiceError.invalidProtocol("apply selected count does not match requested candidates")
        }
        let resultKeys = Set(results.map(\.key))
        guard expectedKeys.isSubset(of: resultKeys) else {
            throw CleanupServiceError.invalidProtocol("apply result omitted a selected candidate")
        }
        guard summary.1 == results.filter({ $0.status == .succeeded }).count,
              summary.2 == results.filter({ $0.status == .skipped }).count,
              summary.3 == results.filter({ $0.status == .failed }).count else {
            throw CleanupServiceError.invalidProtocol("apply summary counts do not match records")
        }
        return CleanupRun(
            results: results,
            selectedCount: summary.0,
            succeededCount: summary.1,
            skippedCount: summary.2,
            failedCount: summary.3
        )
    }

    private static func parseKind(_ value: String) throws -> CleanupCandidateKind {
        guard let kind = CleanupCandidateKind(rawValue: value) else {
            throw CleanupServiceError.invalidProtocol("unknown candidate kind \(value)")
        }
        return kind
    }

    private static func parseKey(_ value: String) throws -> String {
        guard value.count == 64,
              value.unicodeScalars.allSatisfy({
                  ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
              }) else {
            throw CleanupServiceError.invalidProtocol("candidate key is not a lowercase SHA-256 value")
        }
        return value
    }

    private static func parseNonNegativeInt(_ value: String, field: String) throws -> Int {
        guard let parsed = Int(value), parsed >= 0 else {
            throw CleanupServiceError.invalidProtocol("invalid \(field)")
        }
        return parsed
    }

    private static func parseNonNegativeInt64(_ value: String, field: String) throws -> Int64 {
        guard let parsed = Int64(value), parsed >= 0 else {
            throw CleanupServiceError.invalidProtocol("invalid \(field)")
        }
        return parsed
    }

    private static func decode(_ value: String, field: String) throws -> String {
        guard let data = Data(base64Encoded: value), let decoded = String(data: data, encoding: .utf8) else {
            throw CleanupServiceError.invalidProtocol("invalid base64 \(field)")
        }
        return decoded
    }

    private static func optionalDecode(_ value: String, field: String) throws -> String? {
        guard !value.isEmpty else { return nil }
        return try decode(value, field: field)
    }

    private static func invalidFieldCount(_ record: String, _ count: Int) -> CleanupServiceError {
        .invalidProtocol("\(record) has \(count) fields")
    }
}
