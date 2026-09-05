import AppKit

final class NodeServerRowView: NSView {
    private let projectLabel = NSTextField(labelWithString: "")
    private let portsLabel = NSTextField(labelWithString: "")
    private let directoryLabel = NSTextField(labelWithString: "")
    private let commandLabel = NSTextField(labelWithString: "")
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

    func update(server: NodeServer) {
        self.server = server
        projectLabel.stringValue = server.projectName
        portsLabel.stringValue = "PID \(server.pid) · \(server.portSummary)"
        directoryLabel.stringValue = server.workingDirectory?.path ?? "Working directory unavailable"
        commandLabel.stringValue = server.command
        stopButton.toolTip = "Send SIGTERM to PID \(server.pid)"
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

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 3
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = NSStackView()
        titleStack.orientation = .horizontal
        titleStack.alignment = .centerY
        titleStack.spacing = 8

        projectLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        projectLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        projectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        portsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        portsLabel.textColor = .secondaryLabelColor
        portsLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleStack.addArrangedSubview(projectLabel)
        titleStack.addArrangedSubview(portsLabel)

        directoryLabel.font = .systemFont(ofSize: 11)
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        directoryLabel.maximumNumberOfLines = 1

        commandLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        commandLabel.textColor = .tertiaryLabelColor
        commandLabel.lineBreakMode = .byTruncatingMiddle
        commandLabel.maximumNumberOfLines = 1

        contentStack.addArrangedSubview(titleStack)
        contentStack.addArrangedSubview(directoryLabel)
        contentStack.addArrangedSubview(commandLabel)

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 6
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.target = self
        stopButton.action = #selector(stopPressed)
        changePortButton.bezelStyle = .rounded
        changePortButton.controlSize = .small
        changePortButton.target = self
        changePortButton.action = #selector(changePortPressed)
        buttonStack.addArrangedSubview(stopButton)
        buttonStack.addArrangedSubview(changePortButton)

        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 12
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.addArrangedSubview(contentStack)
        rowStack.addArrangedSubview(buttonStack)
        contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonStack.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }
}

final class RestartDialogView: NSView {
    let portField = NSTextField(string: "")
    let commandField = NSTextField(string: "")
    let portEnvironmentCheckbox = NSButton(checkboxWithTitle: "Set PORT environment variable", target: nil, action: nil)

    init(plan: RestartPlan) {
        super.init(frame: NSRect(x: 0, y: 0, width: 440, height: 260))
        portField.stringValue = String(plan.requestedPort)
        commandField.stringValue = plan.command
        setup(plan: plan)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar dialogs are created programmatically")
    }

    private func setup(plan: RestartPlan) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let portLabel = NSTextField(labelWithString: "New port")
        portLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        portField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        portField.controlSize = .regular
        portField.placeholderString = "1–65535"
        portField.translatesAutoresizingMaskIntoConstraints = false
        portField.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let commandLabel = NSTextField(labelWithString: "Restart command")
        commandLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        commandField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        commandField.placeholderString = "Enter a command, for example: npm run dev"
        commandField.usesSingleLineMode = true
        commandField.lineBreakMode = .byTruncatingMiddle
        commandField.translatesAutoresizingMaskIntoConstraints = false
        commandField.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let directoryLabel = NSTextField(wrappingLabelWithString: "Working directory: \(plan.workingDirectory.path)")
        directoryLabel.font = .systemFont(ofSize: 11)
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.maximumNumberOfLines = 2

        let note = plan.inferenceNote.isEmpty
            ? "NodeBar will use a login zsh environment; the original process environment is not copied."
            : "\(plan.inferenceNote) NodeBar will use a login zsh environment; the original process environment is not copied."
        let noteLabel = NSTextField(wrappingLabelWithString: note)
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.maximumNumberOfLines = 3

        portEnvironmentCheckbox.font = .systemFont(ofSize: 11)
        portEnvironmentCheckbox.toolTip = "Some frameworks read PORT; others ignore it."

        stack.addArrangedSubview(portLabel)
        stack.addArrangedSubview(portField)
        stack.addArrangedSubview(commandLabel)
        stack.addArrangedSubview(commandField)
        stack.addArrangedSubview(directoryLabel)
        stack.addArrangedSubview(portEnvironmentCheckbox)
        stack.addArrangedSubview(noteLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

final class NodeBarViewController: NSViewController {
    private let store: ServerStore
    private let actionService: ProcessActionService
    private let planner = RestartPlanner()
    private var rows: [Int32: NodeServerRowView] = [:]
    private var busyPIDs: Set<Int32> = []
    private let countLabel = NSTextField(labelWithString: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let listStack = NSStackView()

    init(store: ServerStore, actionService: ProcessActionService) {
        self.store = store
        self.actionService = actionService
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar is created programmatically")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 480))
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
        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        let titleLabel = NSTextField(labelWithString: "Node servers")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        let refreshButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh") ?? NSImage(), target: self, action: #selector(refreshPressed))
        refreshButton.isBordered = false
        refreshButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshButton.toolTip = "Refresh now"
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(countLabel)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(refreshButton)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 0
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(listStack)
        NSLayoutConstraint.activate([
            listStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            listStack.widthAnchor.constraint(equalTo: documentView.widthAnchor)
        ])

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 370).isActive = true

        stateLabel.font = .systemFont(ofSize: 11)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.lineBreakMode = .byTruncatingTail
        stateLabel.maximumNumberOfLines = 1

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.addArrangedSubview(stateLabel)
        footer.addArrangedSubview(NSView())
        let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitPressed))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small
        footer.addArrangedSubview(quitButton)

        rootStack.addArrangedSubview(header)
        rootStack.addArrangedSubview(scrollView)
        rootStack.addArrangedSubview(footer)
        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
    }

    private func render() {
        countLabel.stringValue = store.servers.isEmpty ? "" : "\(store.servers.count) listening"
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

        let currentPIDs = Set(store.servers.map(\.pid))
        rows = rows.filter { currentPIDs.contains($0.key) }
        listStack.arrangedSubviews.forEach { view in
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if store.servers.isEmpty {
            let emptyLabel = NSTextField(wrappingLabelWithString: store.lastError == nil ? "No Node.js TCP listeners found." : "Refresh failed. Try again after checking lsof permissions.")
            emptyLabel.font = .systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            listStack.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: listStack.widthAnchor, constant: -20).isActive = true
            return
        }

        for server in store.servers {
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
            row.setBusy(busyPIDs.contains(server.pid))
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            let divider = NSBox()
            divider.boxType = .separator
            listStack.addArrangedSubview(divider)
            divider.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
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
