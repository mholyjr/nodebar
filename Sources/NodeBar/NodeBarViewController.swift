import AppKit

private enum NodeBarLayout {
    static let panelWidth: CGFloat = 400
    static let headerHeight: CGFloat = 42
    static let footerHeight: CGFloat = 40
    static let rowHeight: CGFloat = 88
    static let emptyListHeight: CGFloat = 92
    static let minimumPanelHeight: CGFloat = 180
    static let maximumPanelHeight: CGFloat = 450
}

final class NodeServerRowView: NSView {
    private let projectLabel = NSTextField(labelWithString: "")
    private let portsLabel = NSTextField(labelWithString: "")
    private let directoryLabel = NSTextField(labelWithString: "")
    private let pidLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let changePortButton = NSButton(title: "Change port…", target: nil, action: nil)
    private var server: NodeServer

    var onStop: ((NodeServer) -> Void)?
    var onChangePort: ((NodeServer) -> Void)?

    init(server: NodeServer) {
        self.server = server
        super.init(frame: .zero)
        setup()
        update(server: server)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar rows are created programmatically")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NodeBarLayout.rowHeight)
    }

    func update(server: NodeServer) {
        self.server = server
        projectLabel.stringValue = server.projectName
        portsLabel.stringValue = server.ports.map { ":\($0.port)" }.joined(separator: ", ")
        directoryLabel.stringValue = server.workingDirectory?.path ?? "Working directory unavailable"
        pidLabel.stringValue = "PID \(server.pid)"
        directoryLabel.toolTip = server.workingDirectory?.path
        projectLabel.toolTip = "Command: \(server.command)"
        portsLabel.toolTip = "Listening on \(server.portSummary)"
        stopButton.toolTip = "Send SIGTERM to PID \(server.pid)"
        toolTip = "Command: \(server.command)"
        needsLayout = true
    }

    func setBusy(_ busy: Bool) {
        stopButton.isEnabled = !busy
        changePortButton.isEnabled = !busy
    }

    @objc private func stopPressed() {
        onStop?(server)
    }

    @objc private func changePortPressed() {
        onChangePort?(server)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let horizontalPadding: CGFloat = 12
        let actionWidth: CGFloat = 112
        let stopWidth: CGFloat = 54
        let actionGap: CGFloat = 6
        let actionsX = max(horizontalPadding, width - horizontalPadding - actionWidth - actionGap - stopWidth)
        let contentWidth = max(80, width - (horizontalPadding * 2))
        let portWidth: CGFloat = 100
        let projectWidth = max(60, contentWidth - portWidth - 8)

        projectLabel.frame = NSRect(x: horizontalPadding, y: bounds.height - 28, width: projectWidth, height: 20)
        portsLabel.frame = NSRect(x: horizontalPadding + projectWidth + 8, y: bounds.height - 28, width: portWidth, height: 20)
        directoryLabel.frame = NSRect(x: horizontalPadding, y: bounds.height - 51, width: contentWidth, height: 18)
        pidLabel.frame = NSRect(x: horizontalPadding, y: 12, width: 80, height: 18)
        stopButton.frame = NSRect(x: actionsX + actionGap + actionWidth, y: 9, width: stopWidth, height: 24)
        changePortButton.frame = NSRect(x: actionsX, y: 9, width: actionWidth, height: 24)
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.25).cgColor

        projectLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        projectLabel.lineBreakMode = .byTruncatingTail
        projectLabel.maximumNumberOfLines = 1

        portsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        portsLabel.textColor = .controlAccentColor
        portsLabel.alignment = .right
        portsLabel.lineBreakMode = .byTruncatingHead
        portsLabel.maximumNumberOfLines = 1

        directoryLabel.font = .systemFont(ofSize: 11)
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        directoryLabel.maximumNumberOfLines = 1

        pidLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pidLabel.textColor = .secondaryLabelColor

        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.target = self
        stopButton.action = #selector(stopPressed)

        changePortButton.bezelStyle = .rounded
        changePortButton.controlSize = .small
        changePortButton.target = self
        changePortButton.action = #selector(changePortPressed)

        addSubview(projectLabel)
        addSubview(portsLabel)
        addSubview(directoryLabel)
        addSubview(pidLabel)
        addSubview(stopButton)
        addSubview(changePortButton)
    }
}

private final class NodeServerListView: NSView {
    override var isFlipped: Bool { true }
}

final class RestartDialogView: NSView {
    let portField = NSTextField(string: "")
    let commandField = NSTextField(string: "")
    let portEnvironmentCheckbox = NSButton(checkboxWithTitle: "Set PORT environment variable", target: nil, action: nil)

    init(plan: RestartPlan) {
        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: 260))
        portField.stringValue = String(plan.requestedPort)
        commandField.stringValue = plan.command
        setup(plan: plan)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar dialogs are created programmatically")
    }

    private func setup(plan: RestartPlan) {
        let portLabel = NSTextField(labelWithString: "New port")
        portLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        portLabel.frame = NSRect(x: 0, y: 230, width: 100, height: 18)

        portField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        portField.controlSize = .regular
        portField.placeholderString = "1–65535"
        portField.frame = NSRect(x: 0, y: 200, width: 100, height: 24)

        let commandLabel = NSTextField(labelWithString: "Restart command")
        commandLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        commandLabel.frame = NSRect(x: 0, y: 169, width: 180, height: 18)

        commandField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        commandField.placeholderString = "Enter a command, for example: npm run dev"
        commandField.usesSingleLineMode = true
        commandField.lineBreakMode = .byTruncatingMiddle
        commandField.frame = NSRect(x: 0, y: 137, width: 430, height: 24)

        let directoryLabel = NSTextField(wrappingLabelWithString: "Working directory: \(plan.workingDirectory.path)")
        directoryLabel.font = .systemFont(ofSize: 11)
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.frame = NSRect(x: 0, y: 95, width: 430, height: 34)

        let note = plan.inferenceNote.isEmpty
            ? "NodeBar uses a login zsh environment; the original process environment is not copied."
            : "\(plan.inferenceNote) NodeBar uses a login zsh environment; the original process environment is not copied."
        let noteLabel = NSTextField(wrappingLabelWithString: note)
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.frame = NSRect(x: 0, y: 0, width: 430, height: 46)

        portEnvironmentCheckbox.font = .systemFont(ofSize: 11)
        portEnvironmentCheckbox.toolTip = "Some frameworks read PORT; others ignore it."
        portEnvironmentCheckbox.frame = NSRect(x: 0, y: 64, width: 260, height: 22)

        addSubview(portLabel)
        addSubview(portField)
        addSubview(commandLabel)
        addSubview(commandField)
        addSubview(directoryLabel)
        addSubview(portEnvironmentCheckbox)
        addSubview(noteLabel)
    }
}

final class NodeBarViewController: NSViewController {
    private let store: ServerStore
    private let actionService: ProcessActionService
    private let planner = RestartPlanner()
    private var rows: [Int32: NodeServerRowView] = [:]
    private var busyPIDs: Set<Int32> = []
    private let titleLabel = NSTextField(labelWithString: "NodeBar")
    private let countLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let refreshButton = NSButton()
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let listView = NodeServerListView()
    private var panelSize = NSSize(width: NodeBarLayout.panelWidth, height: NodeBarLayout.minimumPanelHeight)

    var onPreferredSizeChange: ((NSSize) -> Void)?

    init(store: ServerStore, actionService: ProcessActionService) {
        self.store = store
        self.actionService = actionService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar is created programmatically")
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: panelSize))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        store.onChange = { [weak self] in
            self?.render()
        }
        render()
    }

    @objc private func refreshPressed() {
        store.refresh()
    }

    @objc private func quitPressed() {
        NSApp.terminate(nil)
    }

    private func setupView() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor

        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.title = ""
        refreshButton.isBordered = false
        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)
        refreshButton.toolTip = "Refresh now"

        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        quitButton.target = self
        quitButton.action = #selector(quitPressed)

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = listView
        stateLabel.font = .systemFont(ofSize: 11)
        stateLabel.lineBreakMode = .byTruncatingTail
        stateLabel.maximumNumberOfLines = 1
        view.addSubview(titleLabel)
        view.addSubview(countLabel)
        view.addSubview(refreshButton)
        view.addSubview(scrollView)
        view.addSubview(stateLabel)
        view.addSubview(quitButton)
    }

    private func applyPanelSize(_ size: NSSize) {
        panelSize = size
        preferredContentSize = size
        view.setFrameSize(size)
        let width = size.width
        let height = size.height
        titleLabel.frame = NSRect(x: 16, y: height - 34, width: 76, height: 22)
        countLabel.frame = NSRect(x: 96, y: height - 33, width: 120, height: 20)
        refreshButton.frame = NSRect(x: width - 43, y: height - 35, width: 26, height: 26)
        scrollView.frame = NSRect(x: 12, y: NodeBarLayout.footerHeight, width: width - 24, height: height - NodeBarLayout.headerHeight - NodeBarLayout.footerHeight)
        stateLabel.frame = NSRect(x: 16, y: 11, width: width - 92, height: 18)
        quitButton.frame = NSRect(x: width - 66, y: 8, width: 52, height: 24)
    }

    private func render() {
        let serverCount = store.servers.count
        countLabel.stringValue = serverCount == 0 ? "" : "\(serverCount) listening"
        if let error = store.lastError {
            stateLabel.stringValue = error
            stateLabel.textColor = .systemRed
        } else if let refresh = store.lastRefresh {
            stateLabel.stringValue = "Updated \(Self.timeFormatter.string(from: refresh))"
            stateLabel.textColor = .secondaryLabelColor
        } else {
            stateLabel.stringValue = "Looking for Node listeners…"
            stateLabel.textColor = .secondaryLabelColor
        }

        let listHeight = serverCount == 0
            ? NodeBarLayout.emptyListHeight
            : CGFloat(min(serverCount, 4)) * NodeBarLayout.rowHeight
        let requestedHeight = NodeBarLayout.headerHeight + NodeBarLayout.footerHeight + listHeight
        let newHeight = min(NodeBarLayout.maximumPanelHeight, max(NodeBarLayout.minimumPanelHeight, requestedHeight))
        let newSize = NSSize(width: NodeBarLayout.panelWidth, height: newHeight)
        if panelSize != newSize {
            applyPanelSize(newSize)
            onPreferredSizeChange?(newSize)
        } else {
            applyPanelSize(panelSize)
        }

        listView.subviews.forEach { $0.removeFromSuperview() }
        if serverCount == 0 {
            listView.frame = NSRect(x: 0, y: 0, width: scrollView.contentView.bounds.width, height: max(scrollView.contentView.bounds.height, NodeBarLayout.emptyListHeight))
            let emptyLabel = NSTextField(wrappingLabelWithString: store.lastError == nil ? "No Node.js TCP listeners found." : "Refresh failed. Try again after checking lsof permissions.")
            emptyLabel.font = .systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: 14, y: 28, width: max(40, listView.bounds.width - 28), height: 40)
            listView.addSubview(emptyLabel)
            return
        }

        let currentPIDs = Set(store.servers.map(\.pid))
        rows = rows.filter { currentPIDs.contains($0.key) }
        let listWidth = scrollView.contentView.bounds.width
        let contentHeight = CGFloat(serverCount) * NodeBarLayout.rowHeight
        listView.frame = NSRect(x: 0, y: 0, width: listWidth, height: max(scrollView.contentView.bounds.height, contentHeight))
        for (index, server) in store.servers.enumerated() {
            let row: NodeServerRowView
            if let existing = rows[server.pid] {
                row = existing
                row.update(server: server)
            } else {
                row = NodeServerRowView(server: server)
                row.onStop = { [weak self] server in self?.stop(server) }
                row.onChangePort = { [weak self] server in self?.changePort(server) }
                rows[server.pid] = row
            }
            row.frame = NSRect(x: 0, y: CGFloat(index) * NodeBarLayout.rowHeight, width: listWidth, height: NodeBarLayout.rowHeight)
            row.setBusy(busyPIDs.contains(server.pid))
            listView.addSubview(row)
            if index < serverCount - 1 {
                let divider = NSBox(frame: NSRect(x: 12, y: CGFloat(index + 1) * NodeBarLayout.rowHeight - 1, width: listWidth - 24, height: 1))
                divider.boxType = .separator
                listView.addSubview(divider)
            }
        }
    }

    private func stop(_ server: NodeServer) {
        guard busyPIDs.insert(server.pid).inserted else { return }
        render()
        actionService.stop(server: server) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.stopped):
                self.busyPIDs.remove(server.pid)
                self.store.refresh()
            case .success(.needsForceKill):
                if self.askToForceKill(pid: server.pid) {
                    self.actionService.forceStop(server: server) { [weak self] forceResult in
                        self?.finishForceAction(pid: server.pid, result: forceResult)
                    }
                } else {
                    self.busyPIDs.remove(server.pid)
                    self.store.refresh()
                }
            case .failure(let error):
                self.busyPIDs.remove(server.pid)
                self.show(error: error)
                self.store.refresh()
            }
        }
    }

    private func changePort(_ server: NodeServer) {
        guard let initialPlan = planner.makePlan(for: server, port: server.ports.first?.port ?? 3000) else {
            show(error: ProcessActionError.missingWorkingDirectory)
            return
        }
        let dialogView = RestartDialogView(plan: initialPlan)
        let alert = NSAlert()
        alert.messageText = "Change port for \(server.projectName)"
        alert.informativeText = "NodeBar will stop PID \(server.pid), then start the reviewed command on the new port."
        alert.accessoryView = dialogView
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let port = UInt16(dialogView.portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
            show(error: ProcessActionError.invalidPort)
            return
        }
        let editedCommand = dialogView.commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var command = editedCommand
        if initialPlan.portArgumentWasInferred, editedCommand == initialPlan.command {
            command = planner.commandByUpdatingKnownPort(editedCommand, port: port)
        }
        let plan = RestartPlan(
            server: server,
            requestedPort: port,
            command: command,
            workingDirectory: initialPlan.workingDirectory,
            portArgumentWasInferred: initialPlan.portArgumentWasInferred,
            inferenceNote: initialPlan.inferenceNote,
            usePortEnvironment: dialogView.portEnvironmentCheckbox.state == .on
        )

        busyPIDs.insert(server.pid)
        render()
        actionService.restart(plan: plan) { [weak self] result in
            self?.finishRestart(server: server, plan: plan, result: result)
        }
    }

    private func finishRestart(server: NodeServer, plan: RestartPlan, result: Result<StopOutcome, ProcessActionError>) {
        switch result {
        case .success(.stopped):
            busyPIDs.remove(server.pid)
            store.refresh()
        case .success(.needsForceKill):
            if askToForceKill(pid: server.pid) {
                actionService.forceKillAndRestart(plan: plan) { [weak self] forceResult in
                    guard let self else { return }
                    switch forceResult {
                    case .success(.stopped):
                        self.busyPIDs.remove(server.pid)
                        self.store.refresh()
                    case .success(.needsForceKill):
                        self.busyPIDs.remove(server.pid)
                        self.show(error: ProcessActionError.signalFailed(pid: server.pid, signal: "SIGKILL", reason: "the process is still alive"))
                        self.store.refresh()
                    case .failure(let error):
                        self.busyPIDs.remove(server.pid)
                        self.show(error: error)
                        self.store.refresh()
                    }
                }
            } else {
                busyPIDs.remove(server.pid)
                store.refresh()
            }
        case .failure(let error):
            busyPIDs.remove(server.pid)
            show(error: error)
            store.refresh()
        }
    }

    private func finishForceAction(pid: Int32, result: Result<StopOutcome, ProcessActionError>) {
        busyPIDs.remove(pid)
        if case .failure(let error) = result {
            show(error: error)
        }
        store.refresh()
    }

    private func askToForceKill(pid: Int32) -> Bool {
        let alert = NSAlert()
        alert.messageText = "PID \(pid) did not stop"
        alert.informativeText = "SIGTERM was sent, but the process is still alive. Force Kill sends SIGKILL after checking that the same process is still running."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Force Kill")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func show(error: ProcessActionError) {
        let alert = NSAlert()
        alert.messageText = "NodeBar could not complete that action"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
