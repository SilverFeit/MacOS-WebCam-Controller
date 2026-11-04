import AppKit
import ServiceManagement
import SwiftUI
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

            // 3. Version, GitHub Updates, Homebrew & CLI (`webcamctl`)
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

                Text("Bundled CLI: `webcamctl list | get | set | stream | preset | who | check-update`")
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
}
