import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let discovery = NodeProcessDiscovery()
    private lazy var store = ServerStore(discovery: discovery)
    private lazy var actionService = ProcessActionService(discovery: discovery)
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var rootViewController: NodeBarRootViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "NodeBar")
        if item.button?.image == nil {
            item.button?.title = "Node"
        }
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "NodeBar"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        let serversController = NodeBarViewController(store: store, actionService: actionService)
        let cleanupController = CleanupViewController()
        let viewController = NodeBarRootViewController(
            serversController: serversController,
            cleanupController: cleanupController
        )
        let nodePopover = NSPopover()
        nodePopover.contentViewController = viewController
        nodePopover.contentSize = viewController.preferredContentSize
        nodePopover.behavior = .transient
        nodePopover.animates = true
        viewController.onPreferredSizeChange = { [weak nodePopover] size in
            nodePopover?.contentSize = size
        }
        popover = nodePopover
        rootViewController = viewController

        store.start()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard rootViewController?.hasRunningCleanupOperation == true else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NodeBarIcon.image(for: .node, size: 56)
        alert.messageText = "Cleanup is still running"
        alert.informativeText = "Wait for it to finish, or cancel the scan in Cleanup."
        alert.addButton(withTitle: "Keep NodeBar Open")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        return .terminateCancel
    }
}
