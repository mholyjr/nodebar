import AppKit

private enum CleanupLayout {
    static let panelWidth: CGFloat = 400
    static let initialPanelHeight: CGFloat = 360
    static let minimumPanelHeight: CGFloat = 320
    static let maximumPanelHeight: CGFloat = 450
    static let headerHeight: CGFloat = 88
    static let footerHeight: CGFloat = 42
    static let rowHeight: CGFloat = 66
    static let protectedRowHeight: CGFloat = 54
}

private final class CleanupListView: NSView {
    override var isFlipped: Bool { true }
}

private final class CleanupCandidateRow: NSView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let pathLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let candidate: CleanupCandidate

    var onToggle: ((String, Bool) -> Void)?

    init(candidate: CleanupCandidate, selected: Bool) {
        self.candidate = candidate
        super.init(frame: .zero)
        checkbox.title = candidate.category
        checkbox.state = selected ? .on : .off
        checkbox.target = self
        checkbox.action = #selector(toggle)
        checkbox.font = .systemFont(ofSize: 12, weight: .semibold)

        pathLabel.stringValue = candidate.path
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.toolTip = candidate.path

        detailLabel.stringValue = Self.detail(for: candidate)
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1

        sizeLabel.stringValue = Self.sizeText(candidate.sizeKB)
        sizeLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        sizeLabel.textColor = .controlAccentColor
        sizeLabel.alignment = .right
        sizeLabel.toolTip = "Current size / reclaim upper bound"

        addSubview(checkbox)
        addSubview(pathLabel)
        addSubview(detailLabel)
        addSubview(sizeLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("Cleanup rows are created programmatically")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let width = bounds.width
        checkbox.frame = NSRect(x: 12, y: 8, width: max(180, width - 116), height: 20)
        sizeLabel.frame = NSRect(x: width - 104, y: 9, width: 92, height: 18)
        pathLabel.frame = NSRect(x: 32, y: 31, width: max(80, width - 44), height: 16)
        detailLabel.frame = NSRect(x: 32, y: 48, width: max(80, width - 44), height: 15)
    }

    @objc private func toggle() {
        onToggle?(candidate.key, checkbox.state == .on)
    }

    private static func detail(for candidate: CleanupCandidate) -> String {
        if candidate.kind == .nodeModules {
            return "\(candidate.itemCount) path(s) · activity \(candidate.activityDate) · \(candidate.ageDays)d old"
        }
        if candidate.kind == .pnpmStore {
            return "Renewable store · reclaim is an upper bound"
        }
        if candidate.kind.isCache {
            return "Renewable cache · reclaim is an upper bound"
        }
        if candidate.kind == .worktreePrune {
            return "Metadata only · branch refs are revalidated before pruning"
        }
        return "Clean worktree · branch and file state are revalidated"
    }

    private static func sizeText(_ sizeKB: Int64) -> String {
        if sizeKB >= 1_048_576 {
            return String(format: "%.1f GiB", Double(sizeKB) / 1_048_576.0)
        }
        if sizeKB >= 1_024 {
            return String(format: "%.1f MiB", Double(sizeKB) / 1_024.0)
        }
        return "\(sizeKB) KiB"
    }
}

private final class CleanupProtectedRow: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let reasonLabel = NSTextField(labelWithString: "")

    init(finding: CleanupProtectedFinding) {
        super.init(frame: .zero)
        titleLabel.stringValue = finding.label
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.toolTip = finding.label

        reasonLabel.stringValue = finding.reason
        reasonLabel.font = .systemFont(ofSize: 10)
        reasonLabel.textColor = .secondaryLabelColor
        reasonLabel.lineBreakMode = .byTruncatingTail
        reasonLabel.maximumNumberOfLines = 1
        reasonLabel.toolTip = finding.reason

        addSubview(titleLabel)
        addSubview(reasonLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("Cleanup protected rows are created programmatically")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 24, y: 8, width: max(80, bounds.width - 36), height: 18)
        reasonLabel.frame = NSRect(x: 24, y: 27, width: max(80, bounds.width - 36), height: 16)
    }
}

final class CleanupViewController: NSViewController, NSTextFieldDelegate {
    private let service: CleanupService
    private let titleLabel = NSTextField(labelWithString: "Cleanup")
    private let summaryLabel = NSTextField(labelWithString: "Preview stale worktrees, dependencies, and renewable caches")
    private let ageLabel = NSTextField(labelWithString: "Older than")
    private let ageField = NSTextField(string: "30")
    private let daysLabel = NSTextField(labelWithString: "days")
    private let scanButton = NSButton(title: "Scan", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let cleanButton = NSButton(title: "Clean Selected…", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Run Scan to preview removable items.")
    private let progressIndicator = NSProgressIndicator()
    private let scrollView = NSScrollView()
    private let listView = CleanupListView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let logLabel = NSTextField(wrappingLabelWithString: "")
    private var audit: CleanupAudit?
    private var selectedKeys = Set<String>()
    private var lastRun: CleanupRun?
    private var isBusy = false
    private var panelSize = NSSize(width: CleanupLayout.panelWidth, height: CleanupLayout.initialPanelHeight)
    private var logLines: [String] = []
    private var shouldFollowLog = true
    private var logScrollObserver: NSObjectProtocol?
    private var logLiveScrollObserver: NSObjectProtocol?
    private var isUpdatingLogScroll = false

    var onPreferredSizeChange: ((NSSize) -> Void)?

    var hasRunningOperation: Bool { isBusy }

    init() {
        service = CleanupService()
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = panelSize
    }

    init(service: CleanupService) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = panelSize
    }

    required init?(coder: NSCoder) {
        fatalError("Cleanup is created programmatically")
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: panelSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        applyLayout()
        renderContent()
        onPreferredSizeChange?(panelSize)
    }

    deinit {
        if let logScrollObserver {
            NotificationCenter.default.removeObserver(logScrollObserver)
        }
        if let logLiveScrollObserver {
            NotificationCenter.default.removeObserver(logLiveScrollObserver)
        }
    }

    @objc private func scanPressed() {
        guard let days = validDays() else {
            show(message: "Choose an age threshold between 1 and 365000 days.", style: .warning)
            return
        }
        selectedKeys.removeAll()
        audit = nil
        lastRun = nil
        isBusy = true
        resetLog()
        setPanelHeight(CleanupLayout.initialPanelHeight)
        scanButton.isEnabled = false
        ageField.isEnabled = false
        cancelButton.isEnabled = true
        cleanButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Scanning…"
        statusLabel.textColor = .secondaryLabelColor
        renderContent()
        service.scan(olderThanDays: days, progress: { [weak self] message in
            self?.setProgress(message)
        }) { [weak self] result in
            guard let self else { return }
            self.isBusy = false
            self.scanButton.isEnabled = true
            self.ageField.isEnabled = true
            self.cancelButton.isEnabled = false
            self.progressIndicator.stopAnimation(nil)
            self.progressIndicator.isHidden = true
            switch result {
            case .success(let audit):
                self.audit = audit
                self.setPanelHeight(audit.candidates.isEmpty ? CleanupLayout.initialPanelHeight : CleanupLayout.maximumPanelHeight)
                self.statusLabel.stringValue = "Found \(audit.candidates.count) safe candidates · \(audit.protectedFindings.count) protected"
                self.statusLabel.textColor = .secondaryLabelColor
            case .failure(let error):
                self.setPanelHeight(CleanupLayout.initialPanelHeight)
                self.statusLabel.stringValue = error.localizedDescription
                self.statusLabel.textColor = .systemRed
                self.show(message: error.localizedDescription, style: .warning)
            }
            self.renderContent()
        }
    }

    @objc private func cancelPressed() {
        guard isBusy else { return }
        statusLabel.stringValue = "Cancelling scan…"
        cancelButton.isEnabled = false
        service.cancel()
    }

    @objc private func cleanPressed() {
        guard let audit, !selectedKeys.isEmpty, !isBusy else { return }
        let selected = audit.candidates.filter { selectedKeys.contains($0.key) }
        guard !selected.isEmpty else {
            selectedKeys.removeAll()
            renderContent()
            return
        }
        let preview = selected.prefix(8).map { "• \($0.category) · \($0.path)" }.joined(separator: "\n")
        let suffix = selected.count > 8 ? "\n• and \(selected.count - 8) more…" : ""
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NodeBarIcon.image(for: .node, size: 56)
        alert.messageText = "Clean \(selected.count) selected item\(selected.count == 1 ? "" : "s")?"
        alert.informativeText = "The script will re-audit and revalidate these exact selections before deleting anything.\n\n\(preview)\(suffix)\n\nDeleted directories are permanent."
        alert.addButton(withTitle: "Clean")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let days = validDays() else {
            show(message: "Choose an age threshold between 1 and 365000 days.", style: .warning)
            return
        }
        isBusy = true
        resetLog()
        setPanelHeight(CleanupLayout.maximumPanelHeight)
        scanButton.isEnabled = false
        ageField.isEnabled = false
        cancelButton.isEnabled = false
        cleanButton.isEnabled = false
        progressIndicator.isHidden = false
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Cleaning selected items…"
        statusLabel.textColor = .secondaryLabelColor
        service.clean(keys: selected.map(\.key), olderThanDays: days, progress: { [weak self] message in
            self?.setProgress(message)
        }) { [weak self] result in
            guard let self else { return }
            self.isBusy = false
            self.scanButton.isEnabled = true
            self.ageField.isEnabled = true
            self.progressIndicator.stopAnimation(nil)
            self.progressIndicator.isHidden = true
            switch result {
            case .success(let run):
                self.lastRun = run
                if let currentAudit = self.audit {
                    let removedKeys = Set(run.results.filter { $0.status == .succeeded }.map(\.key))
                    let remaining = currentAudit.candidates.filter { !removedKeys.contains($0.key) }
                    self.audit = CleanupAudit(
                        candidates: remaining,
                        protectedFindings: currentAudit.protectedFindings,
                        totalUpperBoundKB: remaining.reduce(0) { $0 + $1.sizeKB },
                        scannedAt: currentAudit.scannedAt
                    )
                }
                self.selectedKeys.removeAll()
                self.statusLabel.stringValue = "Clean complete · \(run.succeededCount) removed · \(run.skippedCount) skipped · \(run.failedCount) failed"
                self.statusLabel.textColor = run.failedCount == 0 ? .secondaryLabelColor : .systemRed
            case .failure(let error):
                self.statusLabel.stringValue = error.localizedDescription
                self.statusLabel.textColor = .systemRed
                self.show(message: error.localizedDescription, style: .warning)
            }
            self.renderContent()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === ageField else { return }
        cleanButton.isEnabled = !isBusy && !selectedKeys.isEmpty && validDays() != nil
    }

    private func setupView() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        summaryLabel.font = .systemFont(ofSize: 11)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1

        ageLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        ageField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        ageField.alignment = .right
        ageField.delegate = self
        ageField.controlSize = .small
        daysLabel.font = .systemFont(ofSize: 11)
        daysLabel.textColor = .secondaryLabelColor

        for button in [scanButton, cancelButton, cleanButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.target = self
        }
        scanButton.action = #selector(scanPressed)
        cancelButton.action = #selector(cancelPressed)
        cancelButton.isEnabled = false
        cleanButton.action = #selector(cleanPressed)
        cleanButton.isEnabled = false

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = listView

        logLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logLabel.textColor = .secondaryLabelColor
        logLabel.lineBreakMode = .byCharWrapping
        logLabel.maximumNumberOfLines = 0
        logLabel.isSelectable = true

        logScrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isUpdatingLogScroll else { return }
            self.updateLogFollowState()
        }
        logLiveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.updateLogFollowState()
        }

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 2

        view.addSubview(titleLabel)
        view.addSubview(summaryLabel)
        view.addSubview(ageLabel)
        view.addSubview(ageField)
        view.addSubview(daysLabel)
        view.addSubview(scanButton)
        view.addSubview(cancelButton)
        view.addSubview(cleanButton)
        view.addSubview(statusLabel)
        view.addSubview(progressIndicator)
        view.addSubview(scrollView)
    }

    private func applyLayout() {
        let width = panelSize.width
        let height = panelSize.height
        titleLabel.frame = NSRect(x: 16, y: height - 30, width: 84, height: 20)
        summaryLabel.frame = NSRect(x: 16, y: height - 50, width: width - 32, height: 18)
        ageLabel.frame = NSRect(x: 16, y: height - 78, width: 70, height: 18)
        ageField.frame = NSRect(x: 86, y: height - 80, width: 48, height: 20)
        daysLabel.frame = NSRect(x: 140, y: height - 78, width: 38, height: 18)
        scanButton.frame = NSRect(x: width - 132, y: height - 82, width: 58, height: 24)
        cancelButton.frame = NSRect(x: width - 68, y: height - 82, width: 58, height: 24)
        scrollView.frame = NSRect(x: 12, y: CleanupLayout.footerHeight, width: width - 24, height: height - CleanupLayout.headerHeight - CleanupLayout.footerHeight)
        statusLabel.frame = NSRect(x: 16, y: 17, width: width - 164, height: 16)
        progressIndicator.frame = NSRect(x: width - 148, y: 15, width: 18, height: 18)
        cleanButton.frame = NSRect(x: width - 130, y: 8, width: 118, height: 24)
    }

    private func renderContent() {
        listView.subviews.forEach { $0.removeFromSuperview() }
        let width = max(120, scrollView.contentView.bounds.width)
        var y: CGFloat = 10

        if isBusy {
            renderLog(width: width)
            return
        }

        if let audit {
            let candidateHeader = sectionLabel("Candidates · current size / reclaim upper bound")
            candidateHeader.frame = NSRect(x: 12, y: y, width: width - 24, height: 18)
            listView.addSubview(candidateHeader)
            y += 24

            if audit.candidates.isEmpty {
                let label = NSTextField(wrappingLabelWithString: "No safe candidates found for this threshold.")
                label.font = .systemFont(ofSize: 11)
                label.textColor = .secondaryLabelColor
                label.frame = NSRect(x: 24, y: y, width: width - 48, height: 32)
                listView.addSubview(label)
                y += 42
            } else {
                for candidate in audit.candidates {
                    let row = CleanupCandidateRow(candidate: candidate, selected: selectedKeys.contains(candidate.key))
                    row.frame = NSRect(x: 0, y: y, width: width, height: CleanupLayout.rowHeight)
                    row.onToggle = { [weak self] key, selected in
                        guard let self else { return }
                        if selected { self.selectedKeys.insert(key) } else { self.selectedKeys.remove(key) }
                        self.cleanButton.isEnabled = !self.isBusy && !self.selectedKeys.isEmpty && self.validDays() != nil
                    }
                    listView.addSubview(row)
                    y += CleanupLayout.rowHeight
                }
            }

            let protectedHeader = sectionLabel("Protected findings · never selectable")
            protectedHeader.frame = NSRect(x: 12, y: y, width: width - 24, height: 18)
            listView.addSubview(protectedHeader)
            y += 24
            if audit.protectedFindings.isEmpty {
                let label = NSTextField(labelWithString: "None found")
                label.font = .systemFont(ofSize: 11)
                label.textColor = .secondaryLabelColor
                label.frame = NSRect(x: 24, y: y, width: width - 48, height: 18)
                listView.addSubview(label)
                y += 28
            } else {
                for finding in audit.protectedFindings {
                    let row = CleanupProtectedRow(finding: finding)
                    row.frame = NSRect(x: 0, y: y, width: width, height: CleanupLayout.protectedRowHeight)
                    listView.addSubview(row)
                    y += CleanupLayout.protectedRowHeight
                }
            }

            if let lastRun {
                let resultHeader = sectionLabel("Last clean result")
                resultHeader.frame = NSRect(x: 12, y: y + 8, width: width - 24, height: 18)
                listView.addSubview(resultHeader)
                y += 32
                for result in lastRun.results {
                    let label = NSTextField(wrappingLabelWithString: "\(result.status.rawValue.capitalized): \(result.label) · \(result.detail)")
                    label.font = .systemFont(ofSize: 10)
                    label.textColor = result.status == .failed ? .systemRed : .secondaryLabelColor
                    label.frame = NSRect(x: 24, y: y, width: width - 48, height: 28)
                    listView.addSubview(label)
                    y += 32
                }
            }
        } else {
            emptyLabel.stringValue = isBusy ? "Scanning protected locations and safe candidates…" : "Run Scan to preview removable items.\nNo files are changed by scanning."
            emptyLabel.frame = NSRect(x: 24, y: 42, width: width - 48, height: 44)
            listView.addSubview(emptyLabel)
            y = 110
        }
        listView.frame = NSRect(x: 0, y: 0, width: width, height: max(scrollView.contentView.bounds.height, y + 12))
    }

    private func renderLog(width: CGFloat) {
        let shouldAutoScroll = shouldFollowLog
        isUpdatingLogScroll = true
        let text = logLines.isEmpty ? "Starting cleanup…" : logLines.joined(separator: "\n")
        logLabel.stringValue = text
        let logWidth = max(100, width - 32)
        let font = logLabel.font ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        let measuredHeight = (text as NSString).boundingRect(
            with: NSSize(width: logWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        logLabel.frame = NSRect(
            x: 16,
            y: 12,
            width: logWidth,
            height: max(36, ceil(measuredHeight) + 8)
        )
        listView.addSubview(logLabel)
        listView.frame = NSRect(
            x: 0,
            y: 0,
            width: width,
            height: max(scrollView.contentView.bounds.height, logLabel.frame.maxY + 16)
        )
        guard shouldAutoScroll else {
            isUpdatingLogScroll = false
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.isUpdatingLogScroll = false }
            guard self.isBusy, self.shouldFollowLog else { return }
            self.scrollLogToEnd()
            self.shouldFollowLog = true
        }
    }

    private func scrollLogToEnd() {
        guard let documentView = scrollView.documentView else { return }
        let targetY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func validDays() -> Int? {
        guard let days = Int(ageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), (1...365000).contains(days) else {
            return nil
        }
        return days
    }

    private func setProgress(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isBusy else { return }
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            self.logLines.append(trimmed)
            if self.logLines.count > 500 {
                self.logLines.removeFirst(self.logLines.count - 500)
            }
            self.statusLabel.stringValue = trimmed
            self.statusLabel.toolTip = trimmed
            self.renderContent()
        }
    }

    private func resetLog() {
        isUpdatingLogScroll = true
        logLines.removeAll(keepingCapacity: true)
        shouldFollowLog = true
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isUpdatingLogScroll = false
    }

    private func updateLogFollowState() {
        guard isBusy else { return }
        let visibleBottom = scrollView.contentView.bounds.maxY
        let documentBottom = scrollView.documentView?.bounds.maxY ?? visibleBottom
        shouldFollowLog = documentBottom - visibleBottom <= 18
    }

    private func setPanelHeight(_ height: CGFloat) {
        let clampedHeight = min(CleanupLayout.maximumPanelHeight, max(CleanupLayout.minimumPanelHeight, height))
        let newSize = NSSize(width: CleanupLayout.panelWidth, height: clampedHeight)
        let wasUpdatingLogScroll = isUpdatingLogScroll
        isUpdatingLogScroll = true
        defer { isUpdatingLogScroll = wasUpdatingLogScroll }
        guard panelSize != newSize else {
            applyLayout()
            return
        }
        panelSize = newSize
        preferredContentSize = newSize
        view.setFrameSize(newSize)
        applyLayout()
        onPreferredSizeChange?(newSize)
    }

    private func show(message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.icon = NodeBarIcon.image(for: .node, size: 56)
        alert.messageText = "NodeBar cleanup"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
