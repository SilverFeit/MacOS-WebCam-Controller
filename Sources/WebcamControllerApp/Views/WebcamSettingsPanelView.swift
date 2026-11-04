import SwiftUI
import UVCCore

public struct WebcamSettingsPanelView: View {
    @ObservedObject var manager: CameraManager
    let onWindowLevelChanged: () -> Void

    public init(manager: CameraManager, onWindowLevelChanged: @escaping () -> Void = {}) {
        self.manager = manager
        self.onWindowLevelChanged = onWindowLevelChanged
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Top Camera Dropdown + Pin/Refresh Toolbar (Matches Webcam Settings Panel header)
            HStack(spacing: 8) {
                if manager.cameras.isEmpty {
                    HStack {
                        Image(systemName: "web.camera")
                            .foregroundStyle(.secondary)
                        Text("No USB UVC Webcam Connected")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                } else {
                    Picker(
                        "",
                        selection: Binding(
                            get: { manager.selectedCameraRuntimeID ?? manager.cameras.first?.identity.runtimeID ?? "" },
                            set: { manager.selectedCameraRuntimeID = $0 }
                        )
                    ) {
                        ForEach(manager.cameras) { cam in
                            Text("\(cam.identity.productName)  [\(cam.identity.vidPidHex)]")
                                .tag(cam.identity.runtimeID)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                Button {
                    manager.keepPanelOnTop.toggle()
                    onWindowLevelChanged()
                } label: {
                    Image(systemName: manager.keepPanelOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 12))
                        .foregroundStyle(manager.keepPanelOnTop ? Color.accentColor : .secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Keep Webcam Settings Panel floating above Photo Booth / Zoom / OBS")

                Button {
                    manager.scanDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Rescan USB bus and read live UVC registers")
            }

            // Segmented Tab Control: [ Basic | Advanced | Preferences ]
            Picker("", selection: $manager.activePanelTab) {
                ForEach(SettingsPanelTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)

            // Main Tab Body
            if let camera = manager.selectedCamera {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        switch manager.activePanelTab {
                        case .basic:
                            BasicTabView(camera: camera, compact: false, hideUnsupported: false)
                        case .advanced:
                            AdvancedTabView(camera: camera)
                        case .preferences:
                            PreferencesTabView(manager: manager, onWindowLevelChanged: onWindowLevelChanged)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if manager.activePanelTab != .preferences {
                    ManageSettingsFooterView(manager: manager)
                }
            } else {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Connect an External USB Webcam (UVC)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Built-in MacBook FaceTime cameras use Apple's closed ISP rather than USB UVC.\nPlug in any USB UVC webcam to control its physical sensor registers directly.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Scan USB Devices") {
                        manager.scanDevices()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Spacer()
            }

            // Bottom Status, Version & GitHub Update Bar
            AppVersionFooterView(manager: manager, showStatusText: true)
        }
        .padding(14)
        .frame(minWidth: 468, idealWidth: 472, minHeight: 620, idealHeight: 716)
    }
}
