import Foundation

public struct CameraSettingsSnapshot: Codable, Equatable, Sendable {
    // Basic Tab - Exposure
    public var autoExposureMode: Int?
    public var autoExposurePriority: Int?
    public var exposureTime: Int?
    public var gain: Int?

    // Basic Tab - Image / Processing Unit
    public var brightness: Int?
    public var contrast: Int?
    public var contrastAuto: Bool?
    public var hue: Int?
    public var hueAuto: Bool?
    public var saturation: Int?
    public var sharpness: Int?
    public var gamma: Int?

    // Basic Tab - White Balance
    public var whiteBalanceAuto: Bool?
    public var whiteBalanceTemperature: Int?

    // Advanced Tab - Anti-flicker, Backlight, Focus, PTZ, Optics
    public var powerLineFrequency: Int?
    public var backlightCompensation: Int?
    public var focusAuto: Bool?
    public var focusAbsolute: Int?
    public var zoomAbsolute: Int?
    public var digitalMultiplier: Int?
    public var panAbsolute: Int?
    public var tiltAbsolute: Int?
    public var irisAbsolute: Int?
    public var rollAbsolute: Int?
    public var scanningMode: Bool?
    public var privacy: Bool?

    // Advanced Tab - VideoStreaming Resolution & Frame Rate
    public var streamCodec: Int?
    public var streamWidth: Int?
    public var streamHeight: Int?
    public var streamFPS: Int?

    public init(
        autoExposureMode: Int? = nil,
        autoExposurePriority: Int? = nil,
        exposureTime: Int? = nil,
        gain: Int? = nil,
        brightness: Int? = nil,
        contrast: Int? = nil,
        contrastAuto: Bool? = nil,
        hue: Int? = nil,
        hueAuto: Bool? = nil,
        saturation: Int? = nil,
        sharpness: Int? = nil,
        gamma: Int? = nil,
        whiteBalanceAuto: Bool? = nil,
        whiteBalanceTemperature: Int? = nil,
        powerLineFrequency: Int? = nil,
        backlightCompensation: Int? = nil,
        focusAuto: Bool? = nil,
        focusAbsolute: Int? = nil,
        zoomAbsolute: Int? = nil,
        digitalMultiplier: Int? = nil,
        panAbsolute: Int? = nil,
        tiltAbsolute: Int? = nil,
        irisAbsolute: Int? = nil,
        rollAbsolute: Int? = nil,
        scanningMode: Bool? = nil,
        privacy: Bool? = nil,
        streamCodec: Int? = nil,
        streamWidth: Int? = nil,
        streamHeight: Int? = nil,
        streamFPS: Int? = nil
    ) {
        self.autoExposureMode = autoExposureMode
        self.autoExposurePriority = autoExposurePriority
        self.exposureTime = exposureTime
        self.gain = gain
        self.brightness = brightness
        self.contrast = contrast
        self.contrastAuto = contrastAuto
        self.hue = hue
        self.hueAuto = hueAuto
        self.saturation = saturation
        self.sharpness = sharpness
        self.gamma = gamma
        self.whiteBalanceAuto = whiteBalanceAuto
        self.whiteBalanceTemperature = whiteBalanceTemperature
        self.powerLineFrequency = powerLineFrequency
        self.backlightCompensation = backlightCompensation
        self.focusAuto = focusAuto
        self.focusAbsolute = focusAbsolute
        self.zoomAbsolute = zoomAbsolute
        self.digitalMultiplier = digitalMultiplier
        self.panAbsolute = panAbsolute
        self.tiltAbsolute = tiltAbsolute
        self.irisAbsolute = irisAbsolute
        self.rollAbsolute = rollAbsolute
        self.scanningMode = scanningMode
        self.privacy = privacy
        self.streamCodec = streamCodec
        self.streamWidth = streamWidth
        self.streamHeight = streamHeight
        self.streamFPS = streamFPS
    }
}

public struct CameraPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var cameraModelKey: String
    public var cameraPersistentID: String
    public var loadAtStart: Bool
    public var snapshot: CameraSettingsSnapshot
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        cameraModelKey: String,
        cameraPersistentID: String,
        loadAtStart: Bool = false,
        snapshot: CameraSettingsSnapshot,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.cameraModelKey = cameraModelKey
        self.cameraPersistentID = cameraPersistentID
        self.loadAtStart = loadAtStart
        self.snapshot = snapshot
        self.createdAt = createdAt
    }
}

public final class PresetStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey = "com.webcamcontroller.savedPresets.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadAll() -> [CameraPreset] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([CameraPreset].self, from: data)) ?? []
    }

    public func saveAll(_ presets: [CameraPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func presets(for identity: CameraIdentity) -> [CameraPreset] {
        loadAll().filter {
            $0.cameraPersistentID.caseInsensitiveCompare(identity.persistentID) == .orderedSame ||
            $0.cameraModelKey.caseInsensitiveCompare(identity.modelKey) == .orderedSame
        }
    }

    @discardableResult
    public func upsertPreset(
        name: String,
        for identity: CameraIdentity,
        snapshot: CameraSettingsSnapshot,
        loadAtStart: Bool = false
    ) -> CameraPreset {
        var all = loadAll()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Custom Preset" : trimmed

        if loadAtStart {
            for idx in all.indices where all[idx].cameraModelKey == identity.modelKey {
                all[idx].loadAtStart = false
            }
        }

        if let existingIdx = all.firstIndex(where: {
            $0.cameraModelKey == identity.modelKey &&
            $0.name.caseInsensitiveCompare(finalName) == .orderedSame
        }) {
            all[existingIdx].snapshot = snapshot
            all[existingIdx].cameraPersistentID = identity.persistentID
            if loadAtStart {
                all[existingIdx].loadAtStart = true
            }
            let updated = all[existingIdx]
            saveAll(all)
            return updated
        } else {
            let created = CameraPreset(
                name: finalName,
                cameraModelKey: identity.modelKey,
                cameraPersistentID: identity.persistentID,
                loadAtStart: loadAtStart,
                snapshot: snapshot
            )
            all.append(created)
            saveAll(all)
            return created
        }
    }

    public func deletePreset(id: UUID) {
        var all = loadAll()
        all.removeAll { $0.id == id }
        saveAll(all)
    }

    public func setLoadAtStart(presetID: UUID?, for identity: CameraIdentity) {
        var all = loadAll()
        for idx in all.indices where all[idx].cameraModelKey == identity.modelKey {
            all[idx].loadAtStart = (all[idx].id == presetID)
        }
        saveAll(all)
    }

    public func startupPreset(for identity: CameraIdentity) -> CameraPreset? {
        presets(for: identity).first(where: { $0.loadAtStart })
    }
}
