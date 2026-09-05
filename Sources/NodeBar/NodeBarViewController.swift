import AppKit

private enum NodeBarLayout {
    static let panelWidth: CGFloat = 400
    static let headerHeight: CGFloat = 42
    static let footerHeight: CGFloat = 38
    static let rowHeight: CGFloat = 92
    static let emptyListHeight: CGFloat = 100
    static let minimumPanelHeight: CGFloat = 180
    static let maximumPanelHeight: CGFloat = 450
}

final class NodeServerRowView: NSView {
    private let frameworkImageView = NSImageView(frame: .zero)
    private let projectLabel = NSTextField(labelWithString: "")
    private let portsLabel = NSTextField(labelWithString: "")
    private let directoryLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let startButton = NSButton(title: "Start", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let configureButton = NSButton(title: "Configure…", target: nil, action: nil)
    private let forgetButton = NSButton(title: "Forget", target: nil, action: nil)
    private var item: ServerItem

    var onStart: ((ServerItem) -> Void)?
    var onStop: ((ServerItem) -> Void)?
    var onConfigure: ((ServerItem) -> Void)?
    var onForget: ((ServerItem) -> Void)?

    init(item: ServerItem) {
        self.item = item
        super.init(frame: .zero)
        setup()
        update(item: item)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar rows are created programmatically")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NodeBarLayout.rowHeight)
    }

    func update(item: ServerItem) {
        self.item = item
        frameworkImageView.image = NodeBarIcon.image(for: item.framework, size: 20)
        projectLabel.stringValue = item.profile.displayName.isEmpty ? "Node server" : item.profile.displayName
        if let currentPort = item.currentPort {
            let preference = item.profile.preferredPort != currentPort ? " · pref :\(item.profile.preferredPort)" : ""
            portsLabel.stringValue = ":\(currentPort)\(preference)"
        } else {
            portsLabel.stringValue = "pref :\(item.profile.preferredPort)"
        }
        directoryLabel.stringValue = item.profile.workingDirectory.isEmpty
            ? "Project directory unavailable"
            : item.profile.workingDirectory
        statusLabel.stringValue = item.liveServer.map { "PID \($0.pid)" } ?? "Stopped"
        statusLabel.textColor = item.isRunning ? .controlAccentColor : .secondaryLabelColor
        directoryLabel.toolTip = item.profile.workingDirectory
        let command = item.profile.command.isEmpty ? "No start command configured." : item.profile.command
        projectLabel.toolTip = "Command: \(command)"
        portsLabel.toolTip = item.liveServer.map { "Listening on \($0.portSummary)" } ?? "NodeBar will use port \(item.profile.preferredPort) when started."
        toolTip = "Command: \(command)"
        stopButton.toolTip = item.liveServer.map { "Send SIGTERM to PID \($0.pid)" }
        startButton.toolTip = "Start on port \(item.profile.preferredPort)"
        needsLayout = true
    }

    func setBusy(_ busy: Bool) {
        startButton.isEnabled = !busy
        stopButton.isEnabled = !busy
        configureButton.isEnabled = !busy
        forgetButton.isEnabled = !busy
    }

    @objc private func startPressed() {
        onStart?(item)
    }

    @objc private func stopPressed() {
        onStop?(item)
    }

    @objc private func configurePressed() {
        onConfigure?(item)
    }

    @objc private func forgetPressed() {
        onForget?(item)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let horizontalPadding: CGFloat = 12
        let contentWidth = max(120, width - horizontalPadding * 2)
        let topY = bounds.height - 30
        let projectX = horizontalPadding + 28
        let portWidth: CGFloat = 120
        let portX = width - horizontalPadding - portWidth
        let projectWidth = max(60, portX - projectX - 8)

        frameworkImageView.frame = NSRect(x: horizontalPadding, y: topY, width: 20, height: 20)
        projectLabel.frame = NSRect(x: projectX, y: topY, width: projectWidth, height: 20)
        portsLabel.frame = NSRect(x: portX, y: topY, width: portWidth, height: 20)
        directoryLabel.frame = NSRect(x: horizontalPadding, y: bounds.height - 53, width: contentWidth, height: 18)

        let gap: CGFloat = 6
        var buttons: [(NSButton, CGFloat)] = [(configureButton, 92)]
        if item.isRunning {
            buttons.append((stopButton, 56))
        } else {
            buttons.append((startButton, 58))
            buttons.append((forgetButton, 58))
        }
        let buttonsWidth = buttons.reduce(0) { $0 + $1.1 } + CGFloat(max(0, buttons.count - 1)) * gap
        let actionsX = max(horizontalPadding, width - horizontalPadding - buttonsWidth)
        statusLabel.frame = NSRect(
            x: horizontalPadding,
            y: 10,
            width: max(70, actionsX - horizontalPadding - 8),
            height: 20
        )

        var buttonX = actionsX
        for (button, buttonWidth) in buttons {
            button.frame = NSRect(x: buttonX, y: 8, width: buttonWidth, height: 25)
            buttonX += buttonWidth + gap
        }
        startButton.isHidden = item.isRunning
        stopButton.isHidden = !item.isRunning
        forgetButton.isHidden = item.isRunning
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

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1

        for button in [startButton, stopButton, configureButton, forgetButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.target = self
        }
        startButton.action = #selector(startPressed)
        stopButton.action = #selector(stopPressed)
        configureButton.action = #selector(configurePressed)
        forgetButton.action = #selector(forgetPressed)

        frameworkImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(frameworkImageView)
        addSubview(projectLabel)
        addSubview(portsLabel)
        addSubview(directoryLabel)
        addSubview(statusLabel)
        addSubview(startButton)
        addSubview(stopButton)
        addSubview(configureButton)
        addSubview(forgetButton)
    }
}

private final class NodeServerListView: NSView {
    override var isFlipped: Bool { true }
}

final class RestartDialogView: NSView, NSTextFieldDelegate {
    let portField = NSTextField(string: "")
    let commandField = NSTextField(string: "")
    let portEnvironmentCheckbox = NSButton(checkboxWithTitle: "Set PORT environment variable", target: nil, action: nil)
    private let scriptLabel = NSTextField(labelWithString: "Script")
    private let scriptPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private var suggestedCommand = ""

    var onScriptChange: ((String?) -> Void)?
    var onPortChange: ((UInt16) -> Void)?

    var selectedScriptName: String? {
        scriptPopup.selectedItem?.representedObject as? String
    }

    var suggestedCommandValue: String {
        suggestedCommand
    }

    init(plan: RestartPlan) {
        suggestedCommand = plan.command
        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: 300))
        portField.stringValue = String(plan.requestedPort)
        commandField.stringValue = plan.command
        setup(plan: plan)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar dialogs are created programmatically")
    }

    func apply(plan: RestartPlan) {
        if commandField.stringValue == suggestedCommand {
            commandField.stringValue = plan.command
        }
        suggestedCommand = plan.command
        noteLabel.stringValue = noteText(for: plan)
    }

    @objc private func scriptChanged() {
        onScriptChange?(selectedScriptName)
    }

    @objc private func portChanged() {
        guard let port = UInt16(portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else { return }
        onPortChange?(port)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === portField else { return }
        portChanged()
    }

    private func setup(plan: RestartPlan) {
        let hasScriptSelector = plan.scriptOptions.count > 1
        let portLabel = NSTextField(labelWithString: "Port on start")
        portLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        portLabel.frame = NSRect(x: 0, y: 276, width: 110, height: 18)

        portField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        portField.controlSize = .regular
        portField.placeholderString = "1–65535"
        portField.delegate = self
        portField.target = self
        portField.action = #selector(portChanged)
        portField.frame = NSRect(x: 0, y: 246, width: 100, height: 24)

        scriptLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        scriptLabel.frame = NSRect(x: 0, y: 214, width: 100, height: 18)
        scriptLabel.isHidden = !hasScriptSelector
        scriptPopup.removeAllItems()
        for option in plan.scriptOptions {
            scriptPopup.addItem(withTitle: option.name)
            scriptPopup.lastItem?.representedObject = option.name
        }
        if let selected = plan.selectedScriptName {
            scriptPopup.selectItem(withTitle: selected)
        }
        scriptPopup.target = self
        scriptPopup.action = #selector(scriptChanged)
        scriptPopup.isHidden = !hasScriptSelector
        scriptPopup.frame = NSRect(x: 0, y: 181, width: 210, height: 24)

        let commandLabel = NSTextField(labelWithString: "Start command")
        commandLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        commandLabel.frame = NSRect(x: 0, y: hasScriptSelector ? 149 : 214, width: 180, height: 18)

        commandField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        commandField.placeholderString = "Enter a command, for example: npm run dev"
        commandField.usesSingleLineMode = true
        commandField.lineBreakMode = .byTruncatingMiddle
        commandField.frame = NSRect(x: 0, y: hasScriptSelector ? 117 : 181, width: 430, height: 24)

        let directoryLabel = NSTextField(wrappingLabelWithString: "Working directory: \(plan.workingDirectory.path)")
        directoryLabel.font = .systemFont(ofSize: 11)
        directoryLabel.textColor = .secondaryLabelColor
        directoryLabel.frame = NSRect(x: 0, y: hasScriptSelector ? 72 : 118, width: 430, height: 36)

        portEnvironmentCheckbox.font = .systemFont(ofSize: 11)
        portEnvironmentCheckbox.state = plan.usePortEnvironment ? .on : .off
        portEnvironmentCheckbox.toolTip = "Some frameworks read PORT; others ignore it."
        portEnvironmentCheckbox.frame = NSRect(x: 0, y: hasScriptSelector ? 43 : 82, width: 260, height: 22)

        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.frame = NSRect(x: 0, y: 0, width: 430, height: hasScriptSelector ? 44 : 72)
        noteLabel.stringValue = noteText(for: plan)

        addSubview(portLabel)
        addSubview(portField)
        addSubview(scriptLabel)
        addSubview(scriptPopup)
        addSubview(commandLabel)
        addSubview(commandField)
        addSubview(directoryLabel)
        addSubview(portEnvironmentCheckbox)
        addSubview(noteLabel)
    }

    private func noteText(for plan: RestartPlan) -> String {
        let environmentNote = "Uses login-shell environment; original env is not copied."
        return plan.inferenceNote.isEmpty ? environmentNote : "\(plan.inferenceNote)\n\(environmentNote)"
    }
}

final class NodeBarViewController: NSViewController {
    private let store: ServerStore
    private let actionService: ProcessActionService
    private let planner = RestartPlanner()
    private var rows: [UUID: NodeServerRowView] = [:]
    private var busyIDs: Set<UUID> = []
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
        countLabel.frame = NSRect(x: 96, y: height - 33, width: 210, height: 20)
        refreshButton.frame = NSRect(x: width - 43, y: height - 35, width: 26, height: 26)
        scrollView.frame = NSRect(
            x: 12,
            y: NodeBarLayout.footerHeight,
            width: width - 24,
            height: max(1, height - NodeBarLayout.headerHeight - NodeBarLayout.footerHeight)
        )
        stateLabel.frame = NSRect(x: 16, y: 9, width: width - 92, height: 18)
        quitButton.frame = NSRect(x: width - 66, y: 6, width: 52, height: 24)
    }

    private func render() {
        let items = store.servers
        let runningCount = items.filter(\.isRunning).count
        let stoppedCount = items.count - runningCount
        countLabel.stringValue = items.isEmpty ? "" : "\(runningCount) running · \(stoppedCount) stopped"
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

        let listHeight = items.isEmpty
            ? NodeBarLayout.emptyListHeight
            : CGFloat(min(items.count, 4)) * NodeBarLayout.rowHeight
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
        let listWidth = max(1, scrollView.contentView.bounds.width)
        if items.isEmpty {
            listView.frame = NSRect(x: 0, y: 0, width: listWidth, height: max(scrollView.contentView.bounds.height, NodeBarLayout.emptyListHeight))
            let message = store.lastError == nil
                ? "No saved Node.js servers yet."
                : "Refresh failed. Check lsof permissions and try again."
            let emptyLabel = NSTextField(wrappingLabelWithString: message)
            emptyLabel.font = .systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: 14, y: 28, width: max(40, listWidth - 28), height: 40)
            listView.addSubview(emptyLabel)
            rows.removeAll()
            return
        }

        let currentIDs = Set(items.map(\.id))
        rows = rows.filter { currentIDs.contains($0.key) }
        let contentHeight = CGFloat(items.count) * NodeBarLayout.rowHeight
        listView.frame = NSRect(x: 0, y: 0, width: listWidth, height: max(scrollView.contentView.bounds.height, contentHeight))
        for (index, item) in items.enumerated() {
            let row: NodeServerRowView
            if let existing = rows[item.id] {
                row = existing
                row.update(item: item)
            } else {
                row = NodeServerRowView(item: item)
                row.onStart = { [weak self] item in self?.start(item) }
                row.onStop = { [weak self] item in self?.stop(item) }
                row.onConfigure = { [weak self] item in self?.configure(item) }
                row.onForget = { [weak self] item in self?.forget(item) }
                rows[item.id] = row
            }
            row.frame = NSRect(x: 0, y: CGFloat(index) * NodeBarLayout.rowHeight, width: listWidth, height: NodeBarLayout.rowHeight)
            row.setBusy(busyIDs.contains(item.id))
            listView.addSubview(row)
            if index < items.count - 1 {
                let divider = NSBox(frame: NSRect(x: 12, y: CGFloat(index + 1) * NodeBarLayout.rowHeight - 1, width: max(1, listWidth - 24), height: 1))
                divider.boxType = .separator
                listView.addSubview(divider)
            }
        }
    }

    private func start(_ item: ServerItem, plan overridePlan: RestartPlan? = nil) {
        guard !item.isRunning, busyIDs.insert(item.id).inserted else { return }
        guard let plan = overridePlan ?? store.makePlan(for: item) else {
            busyIDs.remove(item.id)
            show(error: ProcessActionError.missingWorkingDirectory)
            return
        }
        store.beginStarting(profileID: item.id)
        render()
        actionService.start(plan: plan) { [weak self] result in
            guard let self else { return }
            self.busyIDs.remove(item.id)
            switch result {
            case .success(let server):
                self.store.attachStarted(server, to: item.id)
            case .failure(let error):
                self.store.cancelStarting(profileID: item.id)
                self.show(error: error)
                self.store.refresh()
            }
        }
    }

    private func stop(_ item: ServerItem) {
        guard let server = item.liveServer, busyIDs.insert(item.id).inserted else { return }
        render()
        actionService.stop(server: server) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.stopped):
                self.busyIDs.remove(item.id)
                self.store.markStopped(profileID: item.id)
                self.store.refresh()
            case .success(.needsForceKill):
                if self.askToForceKill(item: item) {
                    self.actionService.forceStop(server: server) { [weak self] forceResult in
                        self?.finishForceAction(item: item, result: forceResult)
                    }
                } else {
                    self.busyIDs.remove(item.id)
                    self.store.refresh()
                }
            case .failure(let error):
                self.busyIDs.remove(item.id)
                self.show(error: error)
                self.store.refresh()
            }
        }
    }

    private func configure(_ item: ServerItem) {
        guard let initialPlan = store.makePlan(for: item) else {
            show(error: ProcessActionError.missingWorkingDirectory)
            return
        }
        let dialogView = RestartDialogView(plan: initialPlan)
        var latestPlan = initialPlan
        var draft = item.profile

        func updateSuggestion(port: UInt16, scriptName: String?, regenerateCommand: Bool) {
            draft.preferredPort = port
            draft.scriptName = scriptName
            if regenerateCommand {
                draft.inferredCommand = true
            }
            guard let plan = planner.makePlan(for: draft, liveServer: item.liveServer) else { return }
            latestPlan = plan
            dialogView.apply(plan: plan)
        }

        dialogView.onScriptChange = { [weak dialogView] scriptName in
            guard let dialogView,
                  let port = UInt16(dialogView.portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else { return }
            updateSuggestion(port: port, scriptName: scriptName, regenerateCommand: true)
        }
        dialogView.onPortChange = { [weak dialogView] port in
            guard let dialogView else { return }
            updateSuggestion(port: port, scriptName: dialogView.selectedScriptName, regenerateCommand: false)
        }

        let alert = NSAlert()
        alert.messageText = item.isRunning ? "Configure \(item.profile.displayName)" : "Configure saved server"
        alert.informativeText = item.isRunning
            ? "Save settings without restarting, or restart the reviewed command."
            : "Save settings without starting, or start the reviewed command."
        alert.icon = NodeBarIcon.image(for: initialPlan.framework, size: 64)
        alert.accessoryView = dialogView
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: item.isRunning ? "Restart" : "Start")
        alert.addButton(withTitle: "Cancel")
        alert.layout()
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return }

        guard let port = UInt16(dialogView.portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
            show(error: ProcessActionError.invalidPort)
            return
        }
        let editedCommand = dialogView.commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let generatedCommand = dialogView.suggestedCommandValue
        let savedProfile = ServerProfile(
            id: item.profile.id,
            displayName: item.profile.displayName,
            framework: latestPlan.framework,
            workingDirectory: latestPlan.workingDirectory.path,
            command: editedCommand,
            inferredCommand: editedCommand == generatedCommand && latestPlan.portArgumentWasInferred,
            scriptName: dialogView.selectedScriptName ?? latestPlan.selectedScriptName,
            originalPort: item.profile.originalPort,
            preferredPort: port,
            usePortEnvironment: dialogView.portEnvironmentCheckbox.state == .on,
            observedCommand: item.profile.observedCommand,
            observedPort: item.profile.observedPort
        )
        guard store.updateProfile(savedProfile), let updatedItem = store.servers.first(where: { $0.id == item.id }) else {
            show(message: store.lastError ?? "NodeBar could not save this server.")
            return
        }
        guard response == .alertSecondButtonReturn else { return }

        var actionPlan = store.makePlan(for: updatedItem)
        actionPlan?.usePortEnvironment = dialogView.portEnvironmentCheckbox.state == .on
        if updatedItem.isRunning {
            restart(updatedItem, plan: actionPlan)
        } else {
            start(updatedItem, plan: actionPlan)
        }
    }

    private func restart(_ item: ServerItem, plan overridePlan: RestartPlan? = nil) {
        guard item.liveServer != nil, busyIDs.insert(item.id).inserted else { return }
        guard let plan = overridePlan ?? store.makePlan(for: item) else {
            busyIDs.remove(item.id)
            show(error: ProcessActionError.missingWorkingDirectory)
            return
        }
        render()
        actionService.restart(plan: plan) { [weak self] result in
            self?.finishRestart(item: item, plan: plan, result: result)
        }
    }

    private func finishRestart(item: ServerItem, plan: RestartPlan, result: Result<StopOutcome, ProcessActionError>) {
        guard let server = item.liveServer else { return }
        switch result {
        case .success(.stopped):
            busyIDs.remove(item.id)
            store.refresh()
        case .success(.needsForceKill):
            if askToForceKill(item: item) {
                actionService.forceKillAndRestart(plan: plan) { [weak self] forceResult in
                    guard let self else { return }
                    switch forceResult {
                    case .success(.stopped):
                        self.busyIDs.remove(item.id)
                        self.store.refresh()
                    case .success(.needsForceKill):
                        self.busyIDs.remove(item.id)
                        self.show(error: .signalFailed(pid: server.pid, signal: "SIGKILL", reason: "the process is still alive"))
                        self.store.refresh()
                    case .failure(let error):
                        self.busyIDs.remove(item.id)
                        self.show(error: error)
                        self.store.refresh()
                    }
                }
            } else {
                busyIDs.remove(item.id)
                store.refresh()
            }
        case .failure(let error):
            busyIDs.remove(item.id)
            show(error: error)
            store.refresh()
        }
    }

    private func finishForceAction(item: ServerItem, result: Result<StopOutcome, ProcessActionError>) {
        busyIDs.remove(item.id)
        switch result {
        case .success(.stopped):
            store.markStopped(profileID: item.id)
        case .success(.needsForceKill):
            show(error: .signalFailed(pid: item.liveServer?.pid ?? 0, signal: "SIGKILL", reason: "the process is still alive"))
        case .failure(let error):
            show(error: error)
        }
        store.refresh()
    }

    private func forget(_ item: ServerItem) {
        guard !item.isRunning else { return }
        guard store.forget(profileID: item.id) else {
            show(message: store.lastError ?? "NodeBar could not forget this server.")
            return
        }
    }

    private func askToForceKill(item: ServerItem) -> Bool {
        let alert = NSAlert()
        alert.icon = NodeBarIcon.image(for: item.framework, size: 64)
        alert.messageText = "PID \(item.liveServer?.pid ?? 0) did not stop"
        alert.informativeText = "SIGTERM was sent, but the process is still alive. Force Kill sends SIGKILL after checking that the same process is still running."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Force Kill")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func show(error: ProcessActionError) {
        show(message: error.localizedDescription, title: "NodeBar could not complete that action")
    }

    private func show(message: String, title: String = "NodeBar") {
        let alert = NSAlert()
        alert.icon = NodeBarIcon.image(for: .node, size: 64)
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
