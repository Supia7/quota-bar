import AppKit
import QuotaBarUI
import SwiftUI

@MainActor
@main
final class QuotaBarAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = QuotaBarModel()
    private let updater = QuotaBarSparkleUpdater()
    private let resetNotifier = QuotaResetNotifier()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var hostingController: NSHostingController<QuotaMonitorView>?

    static func main() {
        let application = NSApplication.shared
        let delegate = QuotaBarAppDelegate()
        application.delegate = delegate
        // Start as a regular app so LaunchServices/Control Center fully
        // initializes the status-item scene before we hide the Dock entry.
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.resetHandler = { [weak self] events in
            self?.resetNotifier.notify(events)
        }
        configureStatusItem()
        configurePopover()
        // The app is a menu-bar accessory after its status-item scene exists.
        NSApp.setActivationPolicy(.accessory)
        scheduleVisibilityFallbackCheck()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Give Control Center a stable identity instead of a PID-derived item
        // name, which can retain a broken visibility/position record on macOS.
        item.autosaveName = "com.supia.quotabar.status-item"
        guard let button = item.button else {
            return
        }

        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: "QuotaBar"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "QuotaBar"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        statusItem = item
    }

    private func configurePopover() {
        let rootView = QuotaMonitorView(
            model: model,
            updateAction: updater.checkForUpdates
        )
        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        // Leave room for the compact header, provider blocks, view switcher,
        // and settings' scroll viewport. Long account lists remain scrollable.
        popover.contentSize = NSSize(width: 420, height: 500)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        hostingController?.view.window?.initialFirstResponder = hostingController?.view
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.state = .off
    }

    private func scheduleVisibilityFallbackCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let statusItem else { return }
            guard !statusItem.isVisible else { return }

            // Do not switch activation policy here. On macOS 26, changing an
            // LSUIElement/accessory app to regular after Control Center has
            // created the status-item scene can make the item disappear.
            NSLog("[QuotaBar] status item is not visible after launch")
        }
    }

}
