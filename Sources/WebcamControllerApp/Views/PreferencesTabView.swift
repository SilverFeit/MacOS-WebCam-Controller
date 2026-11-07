import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UVCCore

public struct PreferencesTabView: View {
    @ObservedObject var manager: CameraManager
    let onWindowLevelChanged: () -> Void

    public init(manager: CameraManager, onWindowLevelChanged: @escaping () -> Void = {}) {
        self.manager = manager
        self.onWindowLevelChanged = onWindowLevelChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Target USB Camera by Hardware ID
            PanelGroupBox("Target USB Camera (Configured by Hardware ID)") {
                if let cam = manager.selectedCamera {
                    let id = cam.identity
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3.5) {
                        GridRow {
                            Text("Device Name:").foregroundStyle(.secondary)
                            Text(id.productName).fontWeight(.medium)
                        }
                        GridRow {
                            Text("Vendor / Product:").foregroundStyle(.secondary)
                            Text("\(id.vidPidHex)  (\(id.vendorName.isEmpty ? "UVC USB" : id.vendorName))")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        GridRow {
                            Text("Location / Serial:").foregroundStyle(.secondary)
                            Text("\(id.locationHex)  ·  SN: \(id.serialNumber.isEmpty ? "N/A" : id.serialNumber)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        GridRow {
                            Text("UVC / Firmware:").foregroundStyle(.secondary)
                            Text("UVC \(id.uvcVersionString) · FW \(id.firmwareHex) · CT=\(id.cameraTerminalId) · PU=\(id.processingUnitId) · XU=\(id.extensionUnits.count)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        GridRow {
                            Text("USB Link:").foregroundStyle(.secondary)
                            Text(id.usbSpeedTitle)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(id.usbLinkWarning == nil ? Color.primary : Color.orange)
                        }
                        GridRow {
                            Text("Configured ID:").foregroundStyle(.secondary)
                            Text(manager.configuredCameraID.isEmpty ? "Auto" : manager.configuredCameraID)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .font(.system(size: 11))

                    HStack(spacing: 8) {
                        Button("Bind Active Camera ID") {
                            manager.pinCurrentCameraAsConfiguredDefault()
                        }
                        .controlSize(.small)

                        Button("Rescan USB Bus") {
                            manager.scanDevices()
                        }
                        .controlSize(.small)

                        Button("Refresh Registers") {
                            cam.refreshAllFromHardware(syncLockedTarget: false)
                            manager.statusMessage = "Read live registers from \(id.productName)"
                        }
                        .controlSize(.small)

                        Button("Copy Camera Report") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(CameraReport.markdown(for: cam), forType: .string)
                            manager.statusMessage = "Camera report copied — paste it into a GitHub issue"
                            NSWorkspace.shared.open(CameraReport.issueURL)
                        }
                        .controlSize(.small)
                        .help("Copies your camera's controls, descriptor and video modes, then opens a GitHub issue to paste it into.")
                    }
                    .padding(.top, 3)
                } else {
                    Text("No UVC-compliant external USB camera detected.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Rescan USB Bus") {
                        manager.scanDevices()
                    }
                    .controlSize(.small)
                }
            }

            // 2. Hardware Persistence, Call Auto-Fix & Menu Bar Behavior
            PanelGroupBox("Hardware Control, Call Fixes & Menu Bar") {
                Toggle(isOn: $manager.isHardwareLockEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lock Hardware Values (Anti-Reset Daemon)")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("Re-injects settings over USB Endpoint 0 if Zoom, Teams, OBS, or Chrome resets the camera.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $manager.fixSlowCallModes) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto-fix slow 5 fps call streams (e.g. WhatsApp -> 1080p@30fps)")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("Upgrades sluggish <= 10 fps modes automatically when a call starts with zero Camera/Mic permissions.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $manager.autoLoadPresetOnConnect) {
                    Text("Automatically apply 'Load at Start' preset when USB camera connects")
                        .font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $manager.compactMenuBarMode) {
                    Text("Hide unsupported hardware sliders inside Menu Bar quick popover")
                        .font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)

                Toggle(
                    isOn: Binding(
                        get: { manager.keepPanelOnTop },
                        set: { newVal in
                            manager.keepPanelOnTop = newVal
                            onWindowLevelChanged()
                        }
                    )
                ) {
                    Text("Keep 'Webcam Settings Panel' floating above other windows")
                        .font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)

                Toggle(
                    isOn: Binding(
                        get: { SMAppService.mainApp.status == .enabled },
                        set: { enable in
                            do {
                                if enable {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                                manager.launchLoginError = nil
                                manager.objectWillChange.send()
                            } catch {
                                manager.launchLoginError = error.localizedDescription
                            }
                        }
                    )
                ) {
                    Text("Launch WebCam Controller automatically at macOS Login")
                        .font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $manager.globalHotkeysEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Global shortcuts (work in any app, no permissions)")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("⌃⌥⌘0 turns your configuration on/off · ⌃⌥⌘1–5 apply saved presets 1–5.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                HStack(spacing: 8) {
                    Text("Floating Stream Stats HUD:")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $manager.streamOverlayMode) {
                        ForEach(StreamOverlayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .padding(.top, 2)

                if let launchLoginError = manager.launchLoginError {
                    Text(launchLoginError)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            // 3. Advanced — Network WebSocket Remote Control (`ws://`)
            PanelGroupBox(
                "Advanced — Network WebSocket Control (ws://)",
                headerTrailing: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(manager.webSocketEnabled ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(manager.webSocketEnabled
                             ? "Active · \(manager.webSocketServer.connectedClientsCount) client\(manager.webSocketServer.connectedClientsCount == 1 ? "" : "s")"
                             : "Disabled")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(manager.webSocketEnabled ? Color.accentColor : .secondary)
                    }
                }
            ) {
                let wsEndpoint = manager.webSocketServer.displayEndpointURL(allowLAN: manager.webSocketAllowLAN)

                Toggle(isOn: $manager.webSocketEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Enable WebSocket Server for Remote Camera Control")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("Control UVC exposure, white balance, PTZ, presets & stream modes over the network via JSON or CLI commands.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                HStack(spacing: 8) {
                    Text("Port:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField(
                        "8765",
                        value: $manager.webSocketPort,
                        formatter: NumberFormatter()
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 64)

                    Toggle(isOn: $manager.webSocketAllowLAN) {
                        Text("Allow LAN access (0.0.0.0)")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .help("When enabled, other computers, phones, Stream Deck or Home Assistant on your local network can connect.")

                    Spacer(minLength: 4)

                    Button("Copy ws://") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(wsEndpoint, forType: .string)
                        manager.statusMessage = "Copied WebSocket endpoint \(wsEndpoint)"
                    }
                    .controlSize(.mini)
                }

                HStack(spacing: 8) {
                    Text("Endpoint:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Text(wsEndpoint)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(manager.webSocketEnabled ? Color.accentColor : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("Token (optional):")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    SecureField("None", text: $manager.webSocketAuthToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10.5, design: .monospaced))
                        .frame(width: 96)
                }

                if let wsErr = manager.webSocketServer.lastError {
                    Text(wsErr)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            // 4. Version, GitHub Updates, Homebrew & CLI (`webcamctl`)
            PanelGroupBox("Version, GitHub Updates, Homebrew & CLI") {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installed Version: v\(manager.updateChecker.currentVersion)")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        Text(manager.updateChecker.statusSummary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(manager.updateChecker.isUpdateAvailable ? Color.accentColor : .secondary)
                    }
                    Spacer()

                    Button("Check Updates") {
                        Task {
                            await manager.updateChecker.checkForUpdates(force: true)
                            manager.statusMessage = manager.updateChecker.statusSummary
                        }
                    }
                    .controlSize(.small)
                    .disabled(manager.updateChecker.isChecking)

                    Button("GitHub Releases ↗") {
                        NSWorkspace.shared.open(manager.updateChecker.releasesRedirectURL)
                    }
                    .controlSize(.small)
                }

                Toggle(isOn: $manager.autoCheckUpdates) {
                    Text("Automatically check GitHub Releases for newer versions")
                        .font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)

                HStack(spacing: 6) {
                    Text(AppBuildInfo.homebrewInstallCommand)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button("Copy brew") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AppBuildInfo.homebrewInstallCommand, forType: .string)
                        manager.statusMessage = "Copied Homebrew install command"
                    }
                    .controlSize(.mini)
                    Button("Open Log") {
                        NSWorkspace.shared.open(DiagnosticsLogger.logFileURL)
                    }
                    .controlSize(.mini)
                }
                .padding(.top, 1)

                HStack(spacing: 6) {
                    Text("Presets:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Export…") { exportPresets() }
                        .controlSize(.mini)
                    Button("Import…") { importPresets() }
                        .controlSize(.mini)
                    Spacer()
                    Text("webcamcontroller://preset/Name")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("Bundled CLI: `webcamctl list | get | set | stream | preset | config | look | ws | report | who | check-update`")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // 4. Recent Call Sessions (shown when non-empty)
            if !manager.recentCallSessions.isEmpty {
                PanelGroupBox("Recent Call Sessions") {
                    ForEach(manager.recentCallSessions.prefix(4)) { session in
                        HStack(spacing: 6) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                            Text(session.appNames)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text("\(session.streamSummary) · \(session.formattedDuration)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Clear History") {
                            manager.clearCallSessionHistory()
                        }
                        .controlSize(.mini)
                    }
                }
            }

            // 5. Hardware Reset & App Quit
            HStack(spacing: 10) {
                Button {
                    manager.selectedCamera?.resetAllToHardwareDefaults()
                    manager.selectedPresetSelection = CameraManager.cameraDefaultPresetSentinel
                    manager.statusMessage = "All UVC hardware registers restored to factory defaults"
                } label: {
                    Label("Restore Hardware Defaults", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .disabled(manager.selectedCamera == nil)

                Button(role: .destructive) {
                    manager.shutdown()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit WebCam Controller", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Preset Export / Import

    private func exportPresets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "WebCam Controller Presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try manager.exportPresets(to: url)
            manager.statusMessage = "Exported \(count) preset\(count == 1 ? "" : "s")"
        } catch {
            manager.statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try manager.importPresets(from: url)
        } catch {
            manager.statusMessage = "Not a WebCam Controller presets file"
        }
    }
}
