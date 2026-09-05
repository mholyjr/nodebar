import Foundation

final class ServerStore {
    private let discovery: NodeProcessDiscovery
    private var refreshTimer: Timer?
    private var refreshInFlight = false

    private(set) var servers: [NodeServer] = []
    private(set) var lastError: String?
    private(set) var lastRefresh: Date?
    var onChange: (() -> Void)?

    init(discovery: NodeProcessDiscovery) {
        self.discovery = discovery
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
                case .success(let servers):
                    self.servers = servers
                    self.lastError = nil
                    self.lastRefresh = Date()
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
                self.onChange?()
            }
        }
    }
}
