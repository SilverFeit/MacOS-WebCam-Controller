import Foundation
import Combine
import CUVCHardware

public enum SettingsPanelTab: String, CaseIterable, Identifiable, Sendable {
    case basic = "Basic"
    case advanced = "Advanced"
    case preferences = "Preferences"

    public var id: String { rawValue }
}

public enum StreamOverlayMode: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case whileInCall = "While in Call"
    case always = "Always"

    public var id: String { rawValue }
}

@MainActor
public final class CameraManager: ObservableObject {
    public nonisolated static let cameraDefaultPresetSentinel = "__CAMERA_DEFAULT__"
    public nonisolated static let externalSyncNotificationName = Notification.Name("com.webcamcontroller.uvc.externalSync")

    public static func sharedDefaults() -> UserDefaults {
        if Bundle.main.bundleIdentifier == AppBuildInfo.bundleIdentifier {
            return .standard
        }
        return UserDefaults(suiteName: AppBuildInfo.bundleIdentifier) ?? .standard
    }

    public nonisolated static func postExternalSyncNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            externalSyncNotificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

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
    @Published public var fixSlowCallModes: Bool {
        didSet { defaults.set(fixSlowCallModes, forKey: Keys.fixSlowCallModes) }
    }
    @Published public var autoCheckUpdates: Bool {
        didSet {
            defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates)
            if autoCheckUpdates {
                Task { await updateChecker.checkForUpdates(force: false) }
            }
        }
    }
    @Published public var streamOverlayMode: StreamOverlayMode {
        didSet {
            defaults.set(streamOverlayMode.rawValue, forKey: Keys.streamOverlayMode)
            isOverlayDismissedForSession = false
        }
    }
    @Published public var isOverlayCollapsed: Bool {
        didSet { defaults.set(isOverlayCollapsed, forKey: Keys.isOverlayCollapsed) }
    }
    @Published public var isOverlayDismissedForSession: Bool = false

    // Live Call & Update Telemetry
    public let updateChecker: UpdateChecker
    @Published public private(set) var isSelectedCameraInCall: Bool = false
    @Published public private(set) var activeCallApps: [ActiveCameraClientApp] = []
    @Published public private(set) var callStartedAt: Date? = nil
    @Published public private(set) var callElapsedSeconds: Int = 0
    @Published public private(set) var upgradedSlowModeFrom: String? = nil
    @Published public private(set) var recentCallSessions: [CameraCallSession] = []

    @Published public var statusMessage: String = ""
    @Published public var isPromptingSavePresetName: Bool = false
    @Published public var presetNameDraft: String = ""
    @Published public var launchLoginError: String? = nil

    private let defaults: UserDefaults
    public let presetStore: PresetStore

    private var hotplugWatcher: OpaquePointer?
    private var lockTimer: Timer?
    private var callMonitorTimer: Timer?
    private var updateTimer: Timer?
    private var deviceCancellable: AnyCancellable?
    private var updateCheckerCancellable: AnyCancellable?
    private var distributedSyncObserver: NSObjectProtocol?
    private var appliedStartupForRuntimeIDs: Set<String> = []
    private var slowModeFixAttemptsInSession: Int = 0
    private var everSeenCallAppsInSession: [String] = []
    private let backgroundMonitorsEnabled: Bool

    private enum Keys {
        static let configuredCameraID = "com.webcamcontroller.configuredCameraID"
        static let isHardwareLockEnabled = "com.webcamcontroller.isHardwareLockEnabled"
        static let autoLoadPresetOnConnect = "com.webcamcontroller.autoLoadPresetOnConnect"
        static let compactMenuBarMode = "com.webcamcontroller.compactMenuBarMode"
        static let keepPanelOnTop = "com.webcamcontroller.keepPanelOnTop"
        static let fixSlowCallModes = "com.webcamcontroller.fixSlowCallModes"
        static let autoCheckUpdates = "com.webcamcontroller.autoCheckUpdates"
        static let streamOverlayMode = "com.webcamcontroller.streamOverlayMode"
        static let isOverlayCollapsed = "com.webcamcontroller.isOverlayCollapsed"
        static let recentCallSessions = "com.webcamcontroller.recentCallSessions.v1"
    }

    public var selectedCamera: UVCCameraDevice? {
        guard let runtimeID = selectedCameraRuntimeID else { return cameras.first }
        return cameras.first(where: { $0.identity.runtimeID == runtimeID }) ?? cameras.first
    }

    public var activeCallAppSummary: String {
        if activeCallApps.isEmpty {
            return isSelectedCameraInCall ? "Active Video App" : "Idle"
        }
        let joined = activeCallApps.map(\.name).joined(separator: ", ")
        let hasGuess = activeCallApps.contains { $0.evidence == .frontmostCameraApp }
        return hasGuess ? "\(joined)?" : joined
    }

    public var formattedCallDuration: String {
        let s = max(0, callElapsedSeconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    public var shouldDisplayFloatingOverlay: Bool {
        switch streamOverlayMode {
        case .off:
            return false
        case .whileInCall:
            return isSelectedCameraInCall && !isOverlayDismissedForSession
        case .always:
            return !isOverlayDismissedForSession
        }
    }

    public init(
        defaults: UserDefaults? = nil,
        enableHotplugWatcher: Bool = true,
        enableBackgroundMonitors: Bool? = nil
    ) {
        let resolvedDefaults = defaults ?? Self.sharedDefaults()
        self.defaults = resolvedDefaults
        self.presetStore = PresetStore(defaults: resolvedDefaults)
        self.updateChecker = UpdateChecker()
        self.backgroundMonitorsEnabled = enableBackgroundMonitors ?? enableHotplugWatcher

        self.configuredCameraID = resolvedDefaults.string(forKey: Keys.configuredCameraID) ?? ""
        self.isHardwareLockEnabled = resolvedDefaults.object(forKey: Keys.isHardwareLockEnabled) as? Bool ?? false
        self.autoLoadPresetOnConnect = resolvedDefaults.object(forKey: Keys.autoLoadPresetOnConnect) as? Bool ?? true
        self.compactMenuBarMode = resolvedDefaults.object(forKey: Keys.compactMenuBarMode) as? Bool ?? true
        self.keepPanelOnTop = resolvedDefaults.object(forKey: Keys.keepPanelOnTop) as? Bool ?? false
        self.fixSlowCallModes = resolvedDefaults.object(forKey: Keys.fixSlowCallModes) as? Bool ?? true
        self.autoCheckUpdates = resolvedDefaults.object(forKey: Keys.autoCheckUpdates) as? Bool ?? true
        self.streamOverlayMode = StreamOverlayMode(rawValue: resolvedDefaults.string(forKey: Keys.streamOverlayMode) ?? "") ?? .off
        self.isOverlayCollapsed = resolvedDefaults.object(forKey: Keys.isOverlayCollapsed) as? Bool ?? false

        if let rawSessions = resolvedDefaults.data(forKey: Keys.recentCallSessions),
           let decoded = try? JSONDecoder().decode([CameraCallSession].self, from: rawSessions) {
            self.recentCallSessions = decoded
        }

        updateCheckerCancellable = updateChecker.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        scanDevices()

        if enableHotplugWatcher {
            startHotplugMonitoring()
        }
        if backgroundMonitorsEnabled {
            startCallAndExternalSyncMonitoring()
            startAutomaticUpdateChecking()
        }
        updateLockTimer()
    }

    public func shutdown() {
        lockTimer?.invalidate()
        lockTimer = nil
        callMonitorTimer?.invalidate()
        callMonitorTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        if let obs = distributedSyncObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
            distributedSyncObserver = nil
        }
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
                    DiagnosticsLogger.note("Applied startup preset '\(startup.name)' to \(cam.identity.productName)")
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

    public func loadDocumentationShowcaseCamera() {
        let showcase = UVCCameraDevice.makeDocumentationShowcaseDevice()
        cameras = [showcase]
        configuredCameraID = showcase.identity.persistentID
        selectedCameraRuntimeID = showcase.identity.runtimeID
        isSelectedCameraInCall = true
        activeCallApps = [ActiveCameraClientApp(name: "Zoom", bundleID: "us.zoom.xos", evidence: .microphoneInput)]
        callStartedAt = Date().addingTimeInterval(-254)
        callElapsedSeconds = 254
        bindSelectedCamera()
        statusMessage = "Direct Endpoint 0 UVC active · 0% video CPU overhead"
    }

    public func clearCallSessionHistory() {
        recentCallSessions = []
        defaults.removeObject(forKey: Keys.recentCallSessions)
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

    // MARK: - Passive Call Activity, Slow-Mode Auto-Fix, CLI Sync & Update Checks

    private func startCallAndExternalSyncMonitoring() {
        callMonitorTimer?.invalidate()
        callMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollCallActivity()
            }
        }

        distributedSyncObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.externalSyncNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isHardwareLockEnabled = self.defaults.object(forKey: Keys.isHardwareLockEnabled) as? Bool ?? self.isHardwareLockEnabled
                self.selectedCamera?.refreshAllFromHardware(syncLockedTarget: true)
                self.reloadPresetsForSelectedCamera()
                self.statusMessage = "Synced live changes from webcamctl CLI"
            }
        }
    }

    private func startAutomaticUpdateChecking() {
        if autoCheckUpdates {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await updateChecker.checkForUpdates(force: false)
            }
        }
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600 * 6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoCheckUpdates else { return }
                await self.updateChecker.checkForUpdates(force: false)
            }
        }
    }

    private func pollCallActivity() {
        guard let cam = selectedCamera, cam.isConnected else {
            finishCallSessionIfNeeded()
            return
        }

        cam.refreshActiveStreamState(preserveUserSelection: true)
        let cmioStreaming = CameraActivityMonitor.isUVCCameraStreamingInCoreMediaIO(identity: cam.identity)
        let activeNow = cam.isHardwareStreamingActive || cmioStreaming

        if activeNow {
            if !isSelectedCameraInCall {
                // New call session started
                isSelectedCameraInCall = true
                callStartedAt = Date()
                callElapsedSeconds = 0
                slowModeFixAttemptsInSession = 0
                upgradedSlowModeFrom = nil
                everSeenCallAppsInSession = []
                isOverlayDismissedForSession = false
                DiagnosticsLogger.note("Stream started on \(cam.identity.productName)")
            } else if let start = callStartedAt {
                callElapsedSeconds = Int(Date().timeIntervalSince(start))
            }

            let detectedApps = CameraActivityMonitor.likelyCameraUsers()
            if !detectedApps.isEmpty {
                activeCallApps = detectedApps
                for app in detectedApps where !everSeenCallAppsInSession.contains(app.name) {
                    everSeenCallAppsInSession.append(app.name)
                }
            }

            // WhatsApp / Slow-Mode Auto-Fix: if an app opened a <= 10 fps mode (and user didn't pick <= 10 fps),
            // upgrade to 1080p@30fps (or best >= 30fps mode) after 2s, capped at 2 attempts per session.
            if fixSlowCallModes,
               callElapsedSeconds >= 2,
               slowModeFixAttemptsInSession < 2,
               let live = cam.liveHardwareStream,
               live.fps <= 10,
               (cam.selectedStream?.fps ?? 30) > 10 {
                slowModeFixAttemptsInSession += 1
                let previousSummary = "\(live.width)×\(live.height) @ \(live.fps) fps"
                let preferred16x9Candidates: [(Int, Int)] = [(1920, 1080), (1280, 720), (2560, 1440)]
                let chosenTarget = preferred16x9Candidates.lazy.compactMap { (w, h) -> UVCStreamSelection? in
                    guard let sel = UVCStreamValidator.validateSelection(
                        modes: cam.streamModes,
                        desiredCodec: .mjpeg,
                        desiredWidth: w,
                        desiredHeight: h,
                        desiredFPS: 30
                    ), sel.width == w, sel.height == h, sel.fps >= 24 else {
                        return nil
                    }
                    return sel
                }.first ?? UVCStreamValidator.validateSelection(
                    modes: cam.streamModes,
                    desiredCodec: .mjpeg,
                    desiredWidth: 1920,
                    desiredHeight: 1080,
                    desiredFPS: 30
                )
                if let smoothTarget = chosenTarget, smoothTarget.fps >= 24, cam.applyStreamSelection(smoothTarget) {
                    upgradedSlowModeFrom = previousSummary
                    statusMessage = "Auto-fixed slow stream (\(previousSummary) -> \(smoothTarget.width)×\(smoothTarget.height)@\(smoothTarget.fps)fps)"
                    DiagnosticsLogger.note(statusMessage)
                }
            }
        } else {
            finishCallSessionIfNeeded()
        }
    }

    private func finishCallSessionIfNeeded() {
        guard isSelectedCameraInCall else { return }
        defer {
            isSelectedCameraInCall = false
            activeCallApps = []
            callStartedAt = nil
            callElapsedSeconds = 0
            upgradedSlowModeFrom = nil
            everSeenCallAppsInSession = []
        }

        guard let start = callStartedAt else { return }
        let duration = Int(Date().timeIntervalSince(start))
        guard duration >= 3, let cam = selectedCamera else { return }

        let appTitle = everSeenCallAppsInSession.isEmpty
            ? "Video App"
            : everSeenCallAppsInSession.joined(separator: ", ")
        let streamDesc = (cam.liveHardwareStream ?? cam.selectedStream)?.detailedSummary ?? "USB Stream"
        let session = CameraCallSession(
            appNames: appTitle,
            cameraName: cam.identity.productName,
            startedAt: start,
            durationSeconds: duration,
            streamSummary: streamDesc,
            autoUpgradedFromSlowMode: upgradedSlowModeFrom
        )
        recentCallSessions.insert(session, at: 0)
        if recentCallSessions.count > 25 {
            recentCallSessions = Array(recentCallSessions.prefix(25))
        }
        if let encoded = try? JSONEncoder().encode(recentCallSessions) {
            defaults.set(encoded, forKey: Keys.recentCallSessions)
        }
        DiagnosticsLogger.note("Call session ended: \(appTitle) on \(cam.identity.productName) (\(duration)s, \(streamDesc))")
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
                    DiagnosticsLogger.note("Hardware Lock re-applied \(restored) drifted register(s) on \(cam.identity.productName)")
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
                try? await Task.sleep(nanoseconds: 350_000_000)
                mgr.scanDevices()
            }
        }, unmanagedSelf)
    }
}
