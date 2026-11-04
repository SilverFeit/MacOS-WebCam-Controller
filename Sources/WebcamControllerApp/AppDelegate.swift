import AppKit
import SwiftUI
import UVCCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public let cameraManager = CameraManager()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarStatusItem()
        setupPopover()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsPanel(tab: .basic)
        } else {
            settingsWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        cameraManager.shutdown()
    }

    // MARK: - Menu Bar Webcam Icon & Popover

    private func setupMenuBarStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = IconGenerator.makeMenuBarWebcamIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "WebCam Controller — Direct UVC Hardware Control"
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        let rootView = MenuBarPopoverView(manager: cameraManager) { [weak self] selectedTab in
            self?.openSettingsPanel(tab: selectedTab)
        }
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    @objc private func handleStatusBarClick(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }

        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            openSettingsPanel(tab: .advanced)
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            cameraManager.selectedCamera?.refreshAllFromHardware(syncLockedTarget: false)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()

            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    self?.closePopover()
                }
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Standalone "Webcam Settings Panel" App Window

    public func openSettingsPanel(tab: SettingsPanelTab) {
        closePopover()
        cameraManager.activePanelTab = tab
        cameraManager.selectedCamera?.refreshAllFromHardware(syncLockedTarget: false)

        // Promote to independent regular macOS app while the standalone window is open
        NSApp.setActivationPolicy(.regular)

        if settingsWindow == nil {
            let panelView = WebcamSettingsPanelView(manager: cameraManager) { [weak self] in
                self?.applyWindowLevelPreference()
            }
            let hostingController = NSHostingController(rootView: panelView)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 472, height: 705),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 456, height: 620)
            window.title = "Webcam Settings Panel"
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.settingsWindow = window
        }

        applyWindowLevelPreference()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyWindowLevelPreference() {
        guard let window = settingsWindow else { return }
        window.level = cameraManager.keepPanelOnTop ? .floating : .normal
    }

    public func windowWillClose(_ notification: Notification) {
        // Return cleanly to Menu Bar-only mode when standalone window closes
        NSApp.setActivationPolicy(.accessory)
    }
}
