import Foundation

final class ServerStore {
    private let discovery: NodeProcessDiscovery
    private let planner: RestartPlanner
    private let storage: ServerProfileStorage
    private var refreshTimer: Timer?
    private var refreshInFlight = false
    private var profiles: [ServerProfile]
    private var startingProfileIDs: Set<UUID> = []
    private var persistenceError: String?
    private var persistenceUnavailable = false

    private(set) var servers: [ServerItem]
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?
    var onChange: (() -> Void)?

    init(
        discovery: NodeProcessDiscovery,
        planner: RestartPlanner = RestartPlanner(),
        storage: ServerProfileStorage = ServerProfileStorage()
    ) {
        self.discovery = discovery
        self.planner = planner
        self.storage = storage

        do {
            profiles = try storage.load()
        } catch {
            profiles = []
            persistenceError = error.localizedDescription
            persistenceUnavailable = true
        }
        servers = profiles.map { ServerItem(profile: $0, liveServer: nil) }
        lastError = persistenceError
    }

    func start() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result: Result<[NodeServer], Error>
            do {
                result = .success(try self.discovery.discover())
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                self.refreshInFlight = false
                switch result {
                case .success(let liveServers):
                    let previousProfiles = self.profiles
                    let (reconciledProfiles, liveByProfileID) = self.reconcile(liveServers)
                    self.profiles = reconciledProfiles
                    if previousProfiles != reconciledProfiles {
                        self.persistProfiles()
                    }
                    self.servers = self.makeItems(liveByProfileID: liveByProfileID)
                    self.lastRefresh = Date()
                    self.lastError = self.persistenceError
                case .failure(let error):
                    self.lastError = self.persistenceError ?? error.localizedDescription
                }
                self.onChange?()
            }
        }
    }

    func makePlan(for item: ServerItem) -> RestartPlan? {
        planner.makePlan(for: item.profile, liveServer: item.liveServer)
    }

    func beginStarting(profileID: UUID) {
        startingProfileIDs.insert(profileID)
    }

    func cancelStarting(profileID: UUID) {
        startingProfileIDs.remove(profileID)
    }

    func attachStarted(_ server: NodeServer, to profileID: UUID) {
        startingProfileIDs.remove(profileID)
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        var profile = profiles[index]
        updateObservedValues(of: &profile, from: server)
        profiles[index] = profile
        persistProfiles()
        var liveByProfileID = Dictionary(uniqueKeysWithValues: servers.compactMap { item -> (UUID, NodeServer)? in
            guard let liveServer = item.liveServer else { return nil }
            return (item.profile.id, liveServer)
        })
        liveByProfileID[profileID] = server
        servers = makeItems(liveByProfileID: liveByProfileID)
        lastError = persistenceError
        onChange?()
    }

    func markStopped(profileID: UUID) {
        startingProfileIDs.remove(profileID)
        let liveByProfileID = Dictionary(uniqueKeysWithValues: servers.compactMap { item -> (UUID, NodeServer)? in
            guard item.profile.id != profileID, let liveServer = item.liveServer else { return nil }
            return (item.profile.id, liveServer)
        })
        servers = makeItems(liveByProfileID: liveByProfileID)
        onChange?()
    }

    @discardableResult
    func updateProfile(_ profile: ServerProfile) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return false }
        guard profiles[index] != profile else { return true }
        var updatedProfiles = profiles
        updatedProfiles[index] = profile
        guard persistProfiles(updatedProfiles) else { return false }
        profiles = updatedProfiles
        let liveByProfileID = Dictionary(uniqueKeysWithValues: servers.compactMap { item -> (UUID, NodeServer)? in
            guard let liveServer = item.liveServer else { return nil }
            return (item.profile.id, liveServer)
        })
        servers = makeItems(liveByProfileID: liveByProfileID)
        lastError = persistenceError
        onChange?()
        return true
    }

    @discardableResult
    func forget(profileID: UUID) -> Bool {
        guard let item = servers.first(where: { $0.profile.id == profileID }), !item.isRunning else { return false }
        let updatedProfiles = profiles.filter { $0.id != profileID }
        guard updatedProfiles.count != profiles.count, persistProfiles(updatedProfiles) else { return false }
        profiles = updatedProfiles
        let liveByProfileID = Dictionary(uniqueKeysWithValues: servers.compactMap { item -> (UUID, NodeServer)? in
            guard item.profile.id != profileID, let liveServer = item.liveServer else { return nil }
            return (item.profile.id, liveServer)
        })
        servers = makeItems(liveByProfileID: liveByProfileID)
        lastError = persistenceError
        onChange?()
        return true
    }

    private func reconcile(_ liveServers: [NodeServer]) -> ([ServerProfile], [UUID: NodeServer]) {
        var reconciled = profiles
        var liveByProfileID: [UUID: NodeServer] = [:]
        var assignedProfileIDs: Set<UUID> = []
        let previousLiveByProfileID = Dictionary(uniqueKeysWithValues: servers.compactMap { item -> (UUID, NodeServer)? in
            guard let liveServer = item.liveServer else { return nil }
            return (item.profile.id, liveServer)
        })

        var reservedProfileByPID: [Int32: Int] = [:]
        for liveServer in liveServers {
            let matches = profiles.indices.filter { index in
                let profile = profiles[index]
                guard let profileDirectory = profile.directoryURL,
                      profileDirectory.standardizedFileURL == liveServer.workingDirectory?.standardizedFileURL,
                      let previous = previousLiveByProfileID[profile.id],
                      let expectedStart = previous.identity.startTime,
                      let actualStart = liveServer.identity.startTime else { return false }
                return previous.pid == liveServer.pid && expectedStart == actualStart
            }
            if matches.count == 1, let index = matches.first {
                reservedProfileByPID[liveServer.pid] = index
            }
        }

        let reservedProfileIndices = Set(reservedProfileByPID.values)
        for liveServer in liveServers {
            let profileIndex = reservedProfileByPID[liveServer.pid]
                ?? matchingProfileIndex(
                    for: liveServer,
                    profiles: reconciled,
                    assignedProfileIDs: assignedProfileIDs,
                    reservedProfileIndices: reservedProfileIndices
                )
            let index: Int
            if let profileIndex {
                index = profileIndex
            } else {
                reconciled.append(makeProfile(from: liveServer))
                index = reconciled.index(before: reconciled.endIndex)
            }

            var profile = reconciled[index]
            updateObservedValues(of: &profile, from: liveServer)
            reconciled[index] = profile
            assignedProfileIDs.insert(profile.id)
            liveByProfileID[profile.id] = liveServer
        }
        return (reconciled, liveByProfileID)
    }

    private func matchingProfileIndex(
        for server: NodeServer,
        profiles: [ServerProfile],
        assignedProfileIDs: Set<UUID>,
        reservedProfileIndices: Set<Int>
    ) -> Int? {
        let currentPort = server.ports.first?.port
        let candidates = profiles.indices.filter { index in
            let profile = profiles[index]
            return !assignedProfileIDs.contains(profile.id)
                && !reservedProfileIndices.contains(index)
                && profile.directoryURL?.standardizedFileURL == server.workingDirectory?.standardizedFileURL
        }
        guard !candidates.isEmpty else { return nil }

        func unique(_ predicate: (ServerProfile) -> Bool) -> Int? {
            let matches = candidates.filter { predicate(profiles[$0]) }
            return matches.count == 1 ? matches[0] : nil
        }

        if let match = unique({ profile in
            profile.observedCommand == server.command
                && currentPort.map { profile.observedPort == $0 } == true
        }) {
            return match
        }
        if let match = unique({ profile in
            startingProfileIDs.contains(profile.id) && currentPort.map { profile.preferredPort == $0 } == true
        }) {
            return match
        }
        if let match = unique({ profile in
            currentPort.map { profile.preferredPort == $0 || profile.observedPort == $0 || profile.originalPort == $0 } == true
        }) {
            return match
        }
        return nil
    }

    private func makeProfile(from server: NodeServer) -> ServerProfile {
        let port = server.ports.first?.port ?? 3000
        let plan = planner.makePlan(for: server, port: port)
        let command = plan?.command ?? ""
        return ServerProfile(
            displayName: server.projectName,
            framework: plan?.framework ?? server.framework,
            workingDirectory: server.workingDirectory?.path ?? "",
            command: command,
            inferredCommand: plan?.portArgumentWasInferred ?? false,
            scriptName: plan?.selectedScriptName,
            originalPort: port,
            preferredPort: port,
            usePortEnvironment: false,
            observedCommand: server.command,
            observedPort: port
        )
    }

    private func updateObservedValues(of profile: inout ServerProfile, from server: NodeServer) {
        profile.observedCommand = server.command
        profile.observedPort = server.ports.first?.port ?? profile.observedPort
        if profile.displayName.isEmpty { profile.displayName = server.projectName }
        if profile.framework == .node { profile.framework = server.framework }
    }

    private func makeItems(liveByProfileID: [UUID: NodeServer]) -> [ServerItem] {
        profiles
            .map { ServerItem(profile: $0, liveServer: liveByProfileID[$0.id]) }
            .sorted { lhs, rhs in
                let nameOrder = lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.profile.workingDirectory.localizedCaseInsensitiveCompare(rhs.profile.workingDirectory) == .orderedAscending
            }
    }

    @discardableResult
    private func persistProfiles(_ updatedProfiles: [ServerProfile]? = nil) -> Bool {
        guard !persistenceUnavailable else { return false }
        let values = updatedProfiles ?? profiles
        do {
            try storage.save(values)
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }
}
