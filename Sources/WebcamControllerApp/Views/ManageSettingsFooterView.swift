import SwiftUI
import UVCCore

public struct ManageSettingsFooterView: View {
    @ObservedObject var manager: CameraManager

    public init(manager: CameraManager) {
        self.manager = manager
    }

    private var canDeletePreset: Bool {
        manager.selectedPresetSelection != CameraManager.cameraDefaultPresetSentinel
    }

    public var body: some View {
        PanelGroupBox("Manage Settings") {
            if manager.isPromptingSavePresetName {
                HStack(spacing: 8) {
                    TextField("Preset name (e.g. Daylight, Studio, Night)", text: $manager.presetNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            commitSavePreset()
                        }

                    Button("Save") {
                        commitSavePreset()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Cancel") {
                        manager.isPromptingSavePresetName = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        if let existing = manager.presetsForSelectedCamera.first(where: {
                            $0.id.uuidString == manager.selectedPresetSelection
                        }) {
                            manager.presetNameDraft = existing.name
                        } else {
                            manager.presetNameDraft = "Preset \(manager.presetsForSelectedCamera.count + 1)"
                        }
                        manager.isPromptingSavePresetName = true
                    } label: {
                        Text("Save Current Settings")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .disabled(manager.selectedCamera == nil)

                    Button {
                        manager.deleteSelectedPreset()
                    } label: {
                        Text("Delete Saved Settings")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .disabled(!canDeletePreset)
                }
            }

            HStack(spacing: 10) {
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
                .disabled(manager.selectedCamera == nil)

                Button {
                    manager.toggleLoadAtStartForSelectedPreset()
                } label: {
                    HStack(spacing: 4) {
                        if manager.isSelectedPresetLoadAtStart {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text("Load at Start")
                    }
                    .frame(width: 108)
                }
                .controlSize(.small)
                .disabled(manager.selectedCamera == nil)
            }
        }
    }

    private func commitSavePreset() {
        let trimmed = manager.presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = manager.saveCurrentSettingsAsPreset(name: trimmed)
        manager.isPromptingSavePresetName = false
    }
}
