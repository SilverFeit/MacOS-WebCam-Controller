import SwiftUI
import UVCCore

public struct MenuBarPopoverView: View {
    @ObservedObject var manager: CameraManager
    let onOpenSettingsPanel: (SettingsPanelTab) -> Void

    public init(
        manager: CameraManager,
        onOpenSettingsPanel: @escaping (SettingsPanelTab) -> Void
    ) {
        self.manager = manager
        self.onOpenSettingsPanel = onOpenSettingsPanel
    }

    public var body: some View {
        VStack(spacing: 10) {
            // 1. Menu Bar Header: Camera Selector by ID + Lock + Refresh + Open Window
            HStack(spacing: 8) {
                Image(systemName: "web.camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(manager.selectedCamera != nil ? Color.accentColor : .secondary)

                if manager.cameras.count > 1 {
                    Picker(
                        "",
                        selection: Binding(
                            get: { manager.selectedCameraRuntimeID ?? "" },
                            set: { manager.selectedCameraRuntimeID = $0 }
                        )
                    ) {
                        ForEach(manager.cameras) { cam in
                            Text("\(cam.identity.productName) (\(cam.identity.vidPidHex))")
                                .tag(cam.identity.runtimeID)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                } else if let cam = manager.selectedCamera {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cam.identity.productName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Text("ID \(cam.identity.vidPidHex) · UVC \(cam.identity.uvcVersionString)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    Text("No USB UVC Camera")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    manager.setConfigurationEnabled(!manager.isConfigurationEnabled)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(manager.isConfigurationEnabled ? Color.accentColor : Color.orange)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(manager.isConfigurationEnabled
                      ? "Turn your configuration off (camera returns to factory defaults)"
                      : "Turn your configuration back on (re-applies your saved values)")

                Button {
                    if manager.shouldDisplayFloatingOverlay {
                        manager.isOverlayDismissedForSession = true
                        if manager.streamOverlayMode == .always {
                            manager.streamOverlayMode = .off
                        }
                    } else {
                        manager.isOverlayDismissedForSession = false
                        if manager.streamOverlayMode == .off {
                            manager.streamOverlayMode = manager.isSelectedCameraInCall ? .whileInCall : .always
                        }
                    }
                } label: {
                    Image(systemName: manager.shouldDisplayFloatingOverlay ? "pip.fill" : "pip")
                        .font(.system(size: 11.5))
                        .foregroundStyle(manager.shouldDisplayFloatingOverlay ? Color.accentColor : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Toggle floating Stream Stats HUD overlay")

                Button {
                    manager.isHardwareLockEnabled.toggle()
                } label: {
                    Image(systemName: manager.isHardwareLockEnabled ? "lock.fill" : "lock.open")
                        .font(.system(size: 11.5))
                        .foregroundStyle(manager.isHardwareLockEnabled ? Color.accentColor : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Lock hardware values against resets by video call apps")

                Button {
                    manager.scanDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Read live registers from USB camera")
            }

            Divider()

            // 2. Quick Mode Bar inside Menu Bar: Basic inline | Open Advanced Window | Open Preferences
            HStack(spacing: 6) {
                Button {
                    onOpenSettingsPanel(.basic)
                } label: {
                    Label("Panel", systemImage: "macwindow")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open standalone Webcam Settings Panel on Basic tab")

                Button {
                    onOpenSettingsPanel(.advanced)
                } label: {
                    Label("Advanced…", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Open standalone Webcam Settings Panel on Advanced UVC tab")

                Button {
                    onOpenSettingsPanel(.preferences)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Camera ID & Preferences")
            }

            // 3. Direct Hardware Basic Controls right inside Menu Bar Popover
            if let camera = manager.selectedCamera {
                ScrollView(.vertical, showsIndicators: true) {
                    BasicTabView(
                        camera: camera,
                        compact: true,
                        hideUnsupported: manager.compactMenuBarMode
                    )
                    .padding(.trailing, 2)
                }
                .frame(maxHeight: 435)

                Divider()

                // 4. Quick Preset & Defaults Footer
                HStack(spacing: 8) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { manager.selectedPresetSelection },
                            set: { manager.selectAndApplyPreset(selectionID: $0) }
                        )
                    ) {
                        Text("Camera Default")
                            .tag(CameraManager.cameraDefaultPresetSentinel)
                        if !manager.presetsForSelectedCamera.isEmpty {
                            Divider()
                            ForEach(manager.presetsForSelectedCamera) { preset in
                                Text(preset.loadAtStart ? "★ \(preset.name)" : preset.name)
                                    .tag(preset.id.uuidString)
                            }
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)

                    Button("Defaults") {
                        camera.resetAllToHardwareDefaults()
                        manager.selectedPresetSelection = CameraManager.cameraDefaultPresetSentinel
                        manager.statusMessage = "Restored hardware defaults"
                    }
                    .controlSize(.small)

                    Button {
                        manager.shutdown()
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 11))
                    }
                    .controlSize(.small)
                    .help("Quit WebCam Controller")
                }

                Divider()

                // 5. Bottom Version, Live Call Telemetry & GitHub Update Redirect
                AppVersionFooterView(manager: manager, showStatusText: true)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "web.camera")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Plug in a USB UVC webcam to adjust hardware controls directly.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 24)

                Divider()

                HStack {
                    Button("Rescan USB") { manager.scanDevices() }
                        .controlSize(.small)
                    Spacer()
                    Button("Quit") {
                        manager.shutdown()
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.small)
                }

                Divider()

                AppVersionFooterView(manager: manager, showStatusText: true)
            }
        }
        .padding(12)
        .frame(width: 414)
    }
}
