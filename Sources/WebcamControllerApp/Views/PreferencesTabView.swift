import SwiftUI
import ServiceManagement
import UVCCore

public struct PreferencesTabView: View {
    @ObservedObject var manager: CameraManager
    let onWindowLevelChanged: () -> Void

    public init(manager: CameraManager, onWindowLevelChanged: @escaping () -> Void = {}) {
        self.manager = manager
        self.onWindowLevelChanged = onWindowLevelChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Target USB Camera by Hardware ID
            PanelGroupBox("Target USB Camera (Configured by Hardware ID)") {
                if let cam = manager.selectedCamera {
                    let id = cam.identity
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                        GridRow {
                            Text("Device Name:").foregroundStyle(.secondary)
                            Text(id.productName).fontWeight(.medium)
                        }
                        GridRow {
                            Text("USB Vendor / Product:").foregroundStyle(.secondary)
                            Text("\(id.vidPidHex)  (\(id.vendorName.isEmpty ? "UVC USB" : id.vendorName))")
                                .font(.system(size: 11.5, design: .monospaced))
                        }
                        GridRow {
                            Text("Location / Serial:").foregroundStyle(.secondary)
                            Text("\(id.locationHex)  ·  SN: \(id.serialNumber.isEmpty ? "N/A" : id.serialNumber)")
                                .font(.system(size: 11.5, design: .monospaced))
                        }
                        GridRow {
                            Text("UVC Descriptor:").foregroundStyle(.secondary)
                            Text("UVC \(id.uvcVersionString) · Ifc #\(id.videoControlInterfaceNumber) · CT=\(id.cameraTerminalId) · PU=\(id.processingUnitId)")
                                .font(.system(size: 11.5, design: .monospaced))
                        }
                        GridRow {
                            Text("Configured ID:").foregroundStyle(.secondary)
                            Text(manager.configuredCameraID.isEmpty ? "Auto" : manager.configuredCameraID)
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .font(.system(size: 11.5))

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
                    .padding(.top, 4)
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

            // 2. Hardware Persistence & App Behavior
            PanelGroupBox("Hardware Control & Menu Bar Preferences") {
                Toggle(isOn: $manager.isHardwareLockEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lock Hardware Values (Anti-Reset Daemon)")
                            .font(.system(size: 12, weight: .medium))
                        Text("Automatically re-injects your settings over USB Endpoint 0 if Zoom, Photo Booth, Teams, or Chrome resets the camera.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $manager.autoLoadPresetOnConnect) {
                    Text("Automatically apply 'Load at Start' preset when USB camera connects")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $manager.compactMenuBarMode) {
                    Text("Hide unsupported hardware sliders inside Menu Bar quick popover")
                        .font(.system(size: 12))
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
                    Text("Keep 'Webcam Settings Panel' floating above other windows (Photo Booth / OBS)")
                        .font(.system(size: 12))
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
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)

                if let launchLoginError = manager.launchLoginError {
                    Text(launchLoginError)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
            }

            // 3. Hardware Reset & App Quit
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
