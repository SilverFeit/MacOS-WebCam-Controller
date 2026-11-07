import AppKit
import Combine
import SwiftUI
import UVCCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public let cameraManager = CameraManager()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var streamOverlayController: StreamOverlayController?
    private let hotkeys = GlobalHotkeys()
    private var managerObserver: AnyCancellable?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarStatusItem()
        setupPopover()
        streamOverlayController = StreamOverlayController(manager: cameraManager)

        // Keep the menu bar icon state and the optional global hotkeys in sync with the manager.
        managerObserver = cameraManager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.syncStatusItemAppearance()
                    self?.syncHotkeys()
                }
            }
        }
        syncStatusItemAppearance()
        syncHotkeys()
    }

    /// `webcamcontroller://…` links (Shortcuts "Open URL", Raycast, Stream Deck, `open -g`).
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let parsed = ControllerURLCommand.parse(url) else {
                DiagnosticsLogger.note("Ignoring unrecognized URL: \(url.absoluteString)")
                continue
            }
            cameraManager.execute(parsed.command, cameraSelector: parsed.camera)
        }
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
        hotkeys.disable()
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

        // Right-click, Control-click or a double-click opens the context menu instead of the popover.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) || event.clickCount >= 2 {
            showContextMenu()
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

    // MARK: - Context Menu (right-click / double-click)

    private func showContextMenu() {
        closePopover()

        let menu = NSMenu()
        menu.autoenablesItems = false

        let configOn = cameraManager.isConfigurationEnabled
        let toggle = NSMenuItem(
            title: configOn ? "Turn Configuration Off" : "Turn Configuration On",
            action: #selector(toggleConfiguration),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(toggle)

        let advanced = NSMenuItem(title: "Open Advanced…", action: #selector(openAdvancedFromMenu), keyEquivalent: "")
        advanced.target = self
        advanced.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(advanced)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About WebCam Controller", action: #selector(showAboutPanel), keyEquivalent: "")
        about.target = self
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit WebCam Controller", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        quit.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quit)

        // Attach the menu just for this click so left-click keeps opening the popover.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func toggleConfiguration() {
        cameraManager.setConfigurationEnabled(!cameraManager.isConfigurationEnabled)
    }

    @objc private func openAdvancedFromMenu() {
        openSettingsPanel(tab: .advanced)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showAboutPanel() {
        let credits = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]

        func append(_ text: String, link: URL? = nil) {
            var attributes = baseAttributes
            if let link { attributes[.link] = link }
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }

        append("Direct USB UVC hardware control for macOS.\nNo virtual camera · no Camera or Microphone permission · 0% video CPU.\n\n")
        append("Released under the ")
        append(AppBuildInfo.licenseName, link: AppBuildInfo.licenseURL)
        append(".\nCopyright © \(AppBuildInfo.copyrightYear) ")
        append(AppBuildInfo.authorName, link: AppBuildInfo.authorURL)
        append(".\n\n")
        append("GitHub ↗", link: AppBuildInfo.repositoryURL)

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "WebCam Controller",
            .applicationVersion: AppBuildInfo.currentVersion,
            .version: "",
            .credits: credits
        ])
    }

    // MARK: - Status Item Appearance & Global Hotkeys

    private func syncStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let enabled = cameraManager.isConfigurationEnabled
        button.appearsDisabled = !enabled
        button.toolTip = enabled
            ? "WebCam Controller — Direct UVC Hardware Control"
            : "WebCam Controller — configuration is OFF (camera on factory defaults)"
    }

    private func syncHotkeys() {
        let wanted = cameraManager.globalHotkeysEnabled
        guard wanted != hotkeys.isEnabled else { return }
        guard wanted else {
            hotkeys.disable()
            return
        }
        hotkeys.enable { [weak self] index in
            guard let self else { return }
            let manager = self.cameraManager
            if index == 0 {
                manager.execute(.configuration(.toggle))
            } else {
                manager.execute(.preset(String(index)))
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
