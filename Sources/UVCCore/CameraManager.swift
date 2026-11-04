import Foundation
import Combine
import CUVCHardware

public enum SettingsPanelTab: String, CaseIterable, Identifiable, Sendable {
    case basic = "Basic"
    case advanced = "Advanced"
    case preferences = "Preferences"

    public var id: String { rawValue }
}

@MainActor
public final class CameraManager: ObservableObject {
    public static let cameraDefaultPresetSentinel = "__CAMERA_DEFAULT__"

    @Published public private(set) var cameras: [UVCCameraDevice] = []
    @Published public var selectedCameraRuntimeID: String? {
        didSet {
            guard selectedCameraRuntimeID != oldValue else { return }
            bindSelectedCamera()
        }
    }

    @Published public var activePanelTab: SettingsPanelTab = .basic
    @Published public var selectedPresetSelection: String = CameraManager.cameraDefaultPresetSentinel
    @Published public private(set) var presetsForSelectedCamera: [CameraPreset] = []

    // Persistent Preferences
    @Published public var configuredCameraID: String {
        didSet { defaults.set(configuredCameraID, forKey: Keys.configuredCameraID) }
    }
    @Published public var isHardwareLockEnabled: Bool {
        didSet {
            defaults.set(isHardwareLockEnabled, forKey: Keys.isHardwareLockEnabled)
            updateLockTimer()
        }
    }
    @Published public var autoLoadPresetOnConnect: Bool {
        didSet { defaults.set(autoLoadPresetOnConnect, forKey: Keys.autoLoadPresetOnConnect) }
    }
    @Published public var compactMenuBarMode: Bool {
        didSet { defaults.set(compactMenuBarMode, forKey: Keys.compactMenuBarMode) }
    }
    @Published public var keepPanelOnTop: Bool {
        didSet { defaults.set(keepPanelOnTop, forKey: Keys.keepPanelOnTop) }
    }

    @Published public var statusMessage: String = ""
    @Published public var isPromptingSavePresetName: Bool = false
    @Published public var presetNameDraft: String = ""
    @Published public var launchLoginError: String? = nil

    private let defaults: UserDefaults
    public let presetStore: PresetStore

    private var hotplugWatcher: OpaquePointer?
    private var lockTimer: Timer?
    private var deviceCancellable: AnyCancellable?
    private var appliedStartupForRuntimeIDs: Set<String> = []

    private enum Keys {
        static let configuredCameraID = "com.webcamcontroller.configuredCameraID"
        static let isHardwareLockEnabled = "com.webcamcontroller.isHardwareLockEnabled"
        static let autoLoadPresetOnConnect = "com.webcamcontroller.autoLoadPresetOnConnect"
        static let compactMenuBarMode = "com.webcamcontroller.compactMenuBarMode"
        static let keepPanelOnTop = "com.webcamcontroller.keepPanelOnTop"
    }

    public var selectedCamera: UVCCameraDevice? {
        guard let runtimeID = selectedCameraRuntimeID else { return cameras.first }
        return cameras.first(where: { $0.identity.runtimeID == runtimeID }) ?? cameras.first
    }

    public init(defaults: UserDefaults = .standard, enableHotplugWatcher: Bool = true) {
        self.defaults = defaults
        self.presetStore = PresetStore(defaults: defaults)

        self.configuredCameraID = defaults.string(forKey: Keys.configuredCameraID) ?? ""
        self.isHardwareLockEnabled = defaults.object(forKey: Keys.isHardwareLockEnabled) as? Bool ?? false
        self.autoLoadPresetOnConnect = defaults.object(forKey: Keys.autoLoadPresetOnConnect) as? Bool ?? true
        self.compactMenuBarMode = defaults.object(forKey: Keys.compactMenuBarMode) as? Bool ?? true
        self.keepPanelOnTop = defaults.object(forKey: Keys.keepPanelOnTop) as? Bool ?? false

        scanDevices()

        if enableHotplugWatcher {
            startHotplugMonitoring()
        }
        updateLockTimer()
    }

    public func shutdown() {
        lockTimer?.invalidate()
        lockTimer = nil
        if let watcher = hotplugWatcher {
            cuvc_stop_hotplug_watcher(watcher)
            hotplugWatcher = nil
        }
        for cam in cameras {
            cam.disconnect()
        }
        cameras.removeAll()
    }

    // MARK: - USB Bus Scanning & Hot-Plug

    public func scanDevices() {
        var rawInfos = [CUVCDeviceInfo](repeating: CUVCDeviceInfo(), count: 16)
        let count = Int(cuvc_enumerate_devices(&rawInfos, 16))
        let discoveredInfos = Array(rawInfos.prefix(max(0, count)))

        let discoveredRuntimeIDs = Set(discoveredInfos.map { CameraIdentity(cInfo: $0).runtimeID })

        // Disconnect removed cameras
        var nextCameras: [UVCCameraDevice] = []
        for existing in cameras {
            if discoveredRuntimeIDs.contains(existing.identity.runtimeID) {
                existing.refreshAllFromHardware(syncLockedTarget: false)
                nextCameras.append(existing)
            } else {
                appliedStartupForRuntimeIDs.remove(existing.identity.runtimeID)
                existing.disconnect()
            }
        }

        // Open newly attached cameras
        for info in discoveredInfos {
            let ident = CameraIdentity(cInfo: info)
            if !nextCameras.contains(where: { $0.identity.runtimeID == ident.runtimeID }) {
                if let opened = UVCCameraDevice(cInfo: info) {
                    nextCameras.append(opened)
                }
            }
        }

        cameras = nextCameras

        // Auto-bind configured camera ID on first run if empty
        if configuredCameraID.isEmpty, let first = cameras.first {
            configuredCameraID = first.identity.persistentID
        }

        // Select configured camera by ID if available, otherwise keep current or first
        if let currentID = selectedCameraRuntimeID,
           cameras.contains(where: { $0.identity.runtimeID == currentID }) {
            // Keep active selection unless configured camera just plugged in
            if let preferred = cameras.first(where: { $0.identity.matchesConfiguredID(configuredCameraID) }),
               preferred.identity.runtimeID != currentID,
               !appliedStartupForRuntimeIDs.contains(preferred.identity.runtimeID) {
                selectedCameraRuntimeID = preferred.identity.runtimeID
            } else {
                bindSelectedCamera()
            }
        } else if let preferred = cameras.first(where: { $0.identity.matchesConfiguredID(configuredCameraID) }) {
            selectedCameraRuntimeID = preferred.identity.runtimeID
        } else {
            selectedCameraRuntimeID = cameras.first?.identity.runtimeID
        }

        // Apply startup presets to newly connected cameras if enabled
        if autoLoadPresetOnConnect {
            for cam in cameras where !appliedStartupForRuntimeIDs.contains(cam.identity.runtimeID) {
                appliedStartupForRuntimeIDs.insert(cam.identity.runtimeID)
                if let startup = presetStore.startupPreset(for: cam.identity) {
                    cam.applySnapshot(startup.snapshot)
                    if cam.identity.runtimeID == selectedCamera?.identity.runtimeID {
                        selectedPresetSelection = startup.id.uuidString
                    }
                    statusMessage = "Loaded startup preset '\(startup.name)'"
                }
            }
        }

        if let active = selectedCamera {
            if statusMessage.isEmpty {
                statusMessage = "\(active.identity.productName) [\(active.identity.vidPidHex)]"
            }
        } else {
            statusMessage = "No USB UVC camera detected"
        }
    }

    public func pinCurrentCameraAsConfiguredDefault() {
        guard let cam = selectedCamera else { return }
        configuredCameraID = cam.identity.persistentID
        statusMessage = "Pinned USB ID: \(cam.identity.persistentID)"
    }

    private func bindSelectedCamera() {
        deviceCancellable?.cancel()
        guard let cam = selectedCamera else {
            presetsForSelectedCamera = []
            selectedPresetSelection = Self.cameraDefaultPresetSentinel
            return
        }

        deviceCancellable = cam.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        reloadPresetsForSelectedCamera()
    }

    // MARK: - Preset Management

    public func reloadPresetsForSelectedCamera() {
        guard let cam = selectedCamera else {
            presetsForSelectedCamera = []
            selectedPresetSelection = Self.cameraDefaultPresetSentinel
            return
        }
        presetsForSelectedCamera = presetStore.presets(for: cam.identity)
        if selectedPresetSelection != Self.cameraDefaultPresetSentinel,
           !presetsForSelectedCamera.contains(where: { $0.id.uuidString == selectedPresetSelection }) {
            if let startup = presetsForSelectedCamera.first(where: { $0.loadAtStart }) {
                selectedPresetSelection = startup.id.uuidString
            } else {
                selectedPresetSelection = Self.cameraDefaultPresetSentinel
            }
        }
    }

    public func selectAndApplyPreset(selectionID: String) {
        selectedPresetSelection = selectionID
        guard let cam = selectedCamera else { return }
        if selectionID == Self.cameraDefaultPresetSentinel {
            cam.resetAllToHardwareDefaults()
            statusMessage = "Restored Camera Default settings"
        } else if let preset = presetsForSelectedCamera.first(where: { $0.id.uuidString == selectionID }) {
            cam.applySnapshot(preset.snapshot)
            statusMessage = "Applied preset '\(preset.name)'"
        }
    }

    @discardableResult
    public func saveCurrentSettingsAsPreset(name: String, loadAtStart: Bool = false) -> CameraPreset? {
        guard let cam = selectedCamera else { return nil }
        let snap = cam.captureSnapshot()
        let saved = presetStore.upsertPreset(
            name: name,
            for: cam.identity,
            snapshot: snap,
            loadAtStart: loadAtStart
        )
        reloadPresetsForSelectedCamera()
        selectedPresetSelection = saved.id.uuidString
        statusMessage = "Saved preset '\(saved.name)'"
        return saved
    }

    public func deleteSelectedPreset() {
        guard selectedPresetSelection != Self.cameraDefaultPresetSentinel,
              let uuid = UUID(uuidString: selectedPresetSelection) else {
            return
        }
        let deletedName = presetsForSelectedCamera.first(where: { $0.id == uuid })?.name ?? "Preset"
        presetStore.deletePreset(id: uuid)
        selectedPresetSelection = Self.cameraDefaultPresetSentinel
        reloadPresetsForSelectedCamera()
        statusMessage = "Deleted '\(deletedName)'"
    }

    public var isSelectedPresetLoadAtStart: Bool {
        guard selectedPresetSelection != Self.cameraDefaultPresetSentinel,
              let preset = presetsForSelectedCamera.first(where: { $0.id.uuidString == selectedPresetSelection }) else {
            return false
        }
        return preset.loadAtStart
    }

    public func toggleLoadAtStartForSelectedPreset() {
        guard let cam = selectedCamera else { return }
        if selectedPresetSelection == Self.cameraDefaultPresetSentinel {
            presetStore.setLoadAtStart(presetID: nil, for: cam.identity)
            reloadPresetsForSelectedCamera()
            statusMessage = "Camera Default set on start"
            return
        }
        guard let preset = presetsForSelectedCamera.first(where: { $0.id.uuidString == selectedPresetSelection }) else {
            return
        }
        let newTarget: UUID? = preset.loadAtStart ? nil : preset.id
        presetStore.setLoadAtStart(presetID: newTarget, for: cam.identity)
        reloadPresetsForSelectedCamera()
        statusMessage = newTarget != nil
            ? "'\(preset.name)' will load at start"
            : "Disabled Load at Start for '\(preset.name)'"
    }

    // MARK: - Anti-Reset Hardware Lock & Hotplug C Callback

    private func updateLockTimer() {
        lockTimer?.invalidate()
        lockTimer = nil
        guard isHardwareLockEnabled else { return }
        lockTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isHardwareLockEnabled, let cam = self.selectedCamera else { return }
                let restored = cam.enforceLockedSnapshotIfDrifted()
                if restored > 0 {
                    self.statusMessage = "Hardware Lock re-applied \(restored) value(s)"
                }
            }
        }
    }

    private func startHotplugMonitoring() {
        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        hotplugWatcher = cuvc_start_hotplug_watcher({ context in
            guard let context else { return }
            let mgr = Unmanaged<CameraManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                // Small delay so USB descriptors settle after plug-in
                try? await Task.sleep(nanoseconds: 350_000_000)
                mgr.scanDevices()
            }
        }, unmanagedSelf)
    }
}
