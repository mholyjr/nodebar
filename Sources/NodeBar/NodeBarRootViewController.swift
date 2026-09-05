import AppKit

final class NodeBarRootViewController: NSViewController {
    private let serversController: NodeBarViewController
    private let contentView = NSView()
    private var glassView: NSView?

    var onPreferredSizeChange: ((NSSize) -> Void)?

    init(serversController: NodeBarViewController) {
        self.serversController = serversController
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 400, height: 180)
    }

    required init?(coder: NSCoder) {
        fatalError("NodeBar is created programmatically")
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installSurface()
        addChild(serversController)
        contentView.addSubview(serversController.view)
        serversController.onPreferredSizeChange = { [weak self] size in
            self?.serverSizeChanged(size)
        }
        serverSizeChanged(serversController.preferredContentSize)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        glassView?.frame = view.bounds
        contentView.frame = view.bounds
        serversController.view.frame = view.bounds
    }

    private func serverSizeChanged(_ size: NSSize) {
        let normalized = NSSize(width: 400, height: max(1, size.height))
        preferredContentSize = normalized
        view.setFrameSize(normalized)
        view.needsLayout = true
        onPreferredSizeChange?(normalized)
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
