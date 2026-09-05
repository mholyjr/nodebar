import AppKit

final class NodeBarRootViewController: NSViewController {
    private let serversController: NodeBarViewController
    private let cleanupController: CleanupViewController
    private let tabControl = NSSegmentedControl(labels: ["Servers", "Cleanup"], trackingMode: .selectOne, target: nil, action: nil)
    private var selectedIndex = 0
    private var serversSize = NSSize(width: 400, height: 180)
    private var cleanupSize = NSSize(width: 400, height: 450)

    var onPreferredSizeChange: ((NSSize) -> Void)?

    var hasRunningCleanupOperation: Bool {
        cleanupController.hasRunningOperation
    }

    init(serversController: NodeBarViewController, cleanupController: CleanupViewController) {
        self.serversController = serversController
        self.cleanupController = cleanupController
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 400, height: 214)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar is created programmatically")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: preferredContentSize.height))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabControl.segmentStyle = .texturedRounded
        tabControl.selectedSegment = selectedIndex
        tabControl.target = self
        tabControl.action = #selector(tabChanged)

        addChild(serversController)
        addChild(cleanupController)
        view.addSubview(serversController.view)
        view.addSubview(cleanupController.view)
        view.addSubview(tabControl)

        serversController.onPreferredSizeChange = { [weak self] size in
            self?.childSizeChanged(index: 0, size: size)
        }
        cleanupController.onPreferredSizeChange = { [weak self] size in
            self?.childSizeChanged(index: 1, size: size)
        }
        applySelectedTab()
        childSizeChanged(index: 0, size: serversController.preferredContentSize)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let tabHeight: CGFloat = 32
        let childHeight = max(1, view.bounds.height - tabHeight)
        tabControl.frame = NSRect(x: 12, y: view.bounds.height - tabHeight + 4, width: view.bounds.width - 24, height: 24)
        serversController.view.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: childHeight)
        cleanupController.view.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: childHeight)
    }

    @objc private func tabChanged() {
        selectedIndex = tabControl.selectedSegment
        applySelectedTab()
        let size = selectedIndex == 0 ? serversSize : cleanupSize
        applySize(size)
    }

    private func childSizeChanged(index: Int, size: NSSize) {
        let normalized = NSSize(width: 400, height: max(180, min(450, size.height)))
        if index == 0 {
            serversSize = normalized
        } else {
            cleanupSize = normalized
        }
        if selectedIndex == index {
            applySize(normalized)
        }
    }

    private func applySelectedTab() {
        serversController.view.isHidden = selectedIndex != 0
        cleanupController.view.isHidden = selectedIndex != 1
    }

    private func applySize(_ childSize: NSSize) {
        let size = NSSize(width: 400, height: childSize.height + 32)
        preferredContentSize = size
        view.setFrameSize(size)
        view.needsLayout = true
        onPreferredSizeChange?(size)
    }
}
