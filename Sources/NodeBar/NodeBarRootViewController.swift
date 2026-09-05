import AppKit

final class NodeBarRootViewController: NSViewController {
    private let serversController: NodeBarViewController
    private let cleanupController: CleanupViewController
    private let contentView = NSView()
    private let tabControl = NSSegmentedControl(labels: ["Servers", "Cleanup"], trackingMode: .selectOne, target: nil, action: nil)
    private var selectedIndex = 0
    private var serversSize = NSSize(width: 400, height: 180)
    private var cleanupSize = NSSize(width: 400, height: 360)
    private var glassView: NSView?

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
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSurface()
        tabControl.segmentStyle = .automatic
        tabControl.controlSize = .small
        tabControl.selectedSegment = selectedIndex
        tabControl.target = self
        tabControl.action = #selector(tabChanged)

        addChild(serversController)
        addChild(cleanupController)
        contentView.addSubview(serversController.view)
        contentView.addSubview(cleanupController.view)
        contentView.addSubview(tabControl)

        serversController.onPreferredSizeChange = { [weak self] size in
            self?.childSizeChanged(index: 0, size: size)
        }
        cleanupController.onPreferredSizeChange = { [weak self] size in
            self?.childSizeChanged(index: 1, size: size)
        }
        applySelectedTab()
        childSizeChanged(index: 0, size: serversController.preferredContentSize)
        childSizeChanged(index: 1, size: cleanupController.preferredContentSize)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        glassView?.frame = view.bounds
        contentView.frame = view.bounds

        let tabHeight: CGFloat = 26
        let topInset: CGFloat = 10
        let tabFrame = NSRect(
            x: 16,
            y: view.bounds.height - topInset - tabHeight,
            width: view.bounds.width - 32,
            height: tabHeight
        )
        tabControl.frame = tabFrame
        serversController.view.frame = NSRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: max(1, serversSize.height)
        )
        cleanupController.view.frame = NSRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: max(1, cleanupSize.height)
        )
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
        let size = NSSize(width: 400, height: childSize.height + 46)
        preferredContentSize = size
        view.setFrameSize(size)
        view.needsLayout = true
        onPreferredSizeChange?(size)
    }

    private func installSurface() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.style = .regular
            glass.cornerRadius = 16
            glass.contentView = contentView
            view.addSubview(glass)
            glassView = glass
        } else {
            let visualEffect = NSVisualEffectView(frame: .zero)
            visualEffect.material = .popover
            visualEffect.blendingMode = .withinWindow
            visualEffect.state = .active
            visualEffect.addSubview(contentView)
            view.addSubview(visualEffect)
            glassView = visualEffect
        }
    }
}
