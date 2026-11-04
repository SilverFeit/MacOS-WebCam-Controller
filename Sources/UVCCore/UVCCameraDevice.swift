import Foundation
import Combine
import CUVCHardware

@MainActor
public final class UVCCameraDevice: ObservableObject, Identifiable {
    public nonisolated var id: String { identity.runtimeID }
    public let identity: CameraIdentity

    nonisolated(unsafe) private var handle: OpaquePointer?

    // MARK: - Basic Controls (Exposure)
    @Published public private(set) var autoExposureMode = AutoExposureModeState()
    @Published public private(set) var autoExposurePriority = BooleanControlState()
    @Published public private(set) var exposureTime = NumericRangeControlState()
    @Published public private(set) var gain = NumericRangeControlState()

    // MARK: - Basic Controls (Image Processing Unit)
    @Published public private(set) var brightness = NumericRangeControlState()
    @Published public private(set) var contrast = NumericRangeControlState()
    @Published public private(set) var contrastAuto = BooleanControlState()
    @Published public private(set) var hue = NumericRangeControlState()
    @Published public private(set) var hueAuto = BooleanControlState()
    @Published public private(set) var saturation = NumericRangeControlState()
    @Published public private(set) var sharpness = NumericRangeControlState()
    @Published public private(set) var gamma = NumericRangeControlState()

    // MARK: - Basic Controls (White Balance)
    @Published public private(set) var whiteBalanceAuto = BooleanControlState()
    @Published public private(set) var whiteBalanceTemperature = NumericRangeControlState()

    // MARK: - Advanced Controls (Anti-flicker, Backlight, Focus, PTZ, Optics)
    @Published public private(set) var powerLineFrequency = NumericRangeControlState()
    @Published public private(set) var backlightCompensation = NumericRangeControlState()
    @Published public private(set) var focusAuto = BooleanControlState()
    @Published public private(set) var focusAbsolute = NumericRangeControlState()
    @Published public private(set) var zoomAbsolute = NumericRangeControlState()
    @Published public private(set) var digitalMultiplier = NumericRangeControlState()
    @Published public private(set) var panAbsolute = NumericRangeControlState()
    @Published public private(set) var tiltAbsolute = NumericRangeControlState()
    @Published public private(set) var irisAbsolute = NumericRangeControlState()
    @Published public private(set) var rollAbsolute = NumericRangeControlState()
    @Published public private(set) var scanningMode = BooleanControlState()
    @Published public private(set) var privacy = BooleanControlState()

    // MARK: - Advanced Controls (UVC VideoStreaming Resolutions & Compatible FPS)
    @Published public private(set) var streamModes: [UVCStreamResolutionMode] = []
    @Published public private(set) var defaultStream: UVCStreamSelection?
    @Published public private(set) var selectedStream: UVCStreamSelection?
    @Published public private(set) var liveHardwareStream: UVCStreamSelection?
    @Published public private(set) var isHardwareStreamingActive: Bool = false
    @Published public private(set) var streamStatusNote: String = ""

    /// Desired user-configured state for Anti-Reset Hardware Lock
    public private(set) var lockedTargetSnapshot = CameraSettingsSnapshot()

    public var isConnected: Bool { handle != nil }

    private var ctUnit: UInt8 { UInt8(clamping: max(0, identity.cameraTerminalId)) }
    private var puUnit: UInt8 { UInt8(clamping: max(0, identity.processingUnitId)) }

    public init?(cInfo: CUVCDeviceInfo) {
        let ident = CameraIdentity(cInfo: cInfo)
        guard let opened = cuvc_open_device(ident.locationId, ident.vendorId, ident.productId) else {
            return nil
        }
        self.identity = ident
        self.handle = opened
        refreshAllFromHardware(syncLockedTarget: true)
    }

    private init(showcaseIdentity: CameraIdentity) {
        self.identity = showcaseIdentity
        self.handle = nil
    }

    /// Deterministic offline UVC capability profile used exclusively by `--render-docs-assets`
    /// so UI screenshots can be regenerated cleanly even when no physical camera is attached.
    public static func makeDocumentationShowcaseDevice() -> UVCCameraDevice {
        let ident = CameraIdentity(
            vendorId: 0x041e,
            productId: 0x40a3,
            locationId: 0x00110000,
            firmwareBCD: 0x0214,
            uvcVersionBCD: 0x0150,
            videoControlInterfaceNumber: 0,
            cameraTerminalId: 1,
            processingUnitId: 2,
            productName: "Pro UVC 2K Studio Webcam",
            vendorName: "USB Video Class Hardware",
            serialNumber: "UVC-2K-001"
        )
        let dev = UVCCameraDevice(showcaseIdentity: ident)

        dev.autoExposureMode = AutoExposureModeState(
            isSupported: true,
            canSet: true,
            supportedBitmask: 15,
            defaultMode: .aperturePriority,
            current: .manual
        )
        dev.autoExposurePriority = BooleanControlState(isSupported: true, canSet: true, defaultValue: true, current: false)
        dev.exposureTime = NumericRangeControlState(isSupported: true, canSet: true, minimum: 1, maximum: 2500, step: 1, defaultValue: 156, current: 166)
        dev.gain = NumericRangeControlState(isSupported: true, canSet: true, minimum: 0, maximum: 100, step: 1, defaultValue: 0, current: 18)

        dev.brightness = NumericRangeControlState(isSupported: true, canSet: true, minimum: -64, maximum: 64, step: 1, defaultValue: 0, current: 8)
        dev.contrast = NumericRangeControlState(isSupported: true, canSet: true, minimum: 0, maximum: 100, step: 1, defaultValue: 50, current: 58)
        dev.hue = NumericRangeControlState(isSupported: true, canSet: true, minimum: -40, maximum: 40, step: 1, defaultValue: 0, current: 0)
        dev.saturation = NumericRangeControlState(isSupported: true, canSet: true, minimum: 0, maximum: 128, step: 1, defaultValue: 64, current: 72)
        dev.sharpness = NumericRangeControlState(isSupported: true, canSet: true, minimum: 0, maximum: 10, step: 1, defaultValue: 4, current: 5)
        dev.gamma = NumericRangeControlState(isSupported: true, canSet: true, minimum: 72, maximum: 300, step: 1, defaultValue: 100, current: 100)

        dev.whiteBalanceAuto = BooleanControlState(isSupported: true, canSet: true, defaultValue: true, current: false)
        dev.whiteBalanceTemperature = NumericRangeControlState(isSupported: true, canSet: true, minimum: 2800, maximum: 6500, step: 10, defaultValue: 4600, current: 4450)

        dev.powerLineFrequency = NumericRangeControlState(isSupported: true, canSet: true, minimum: 0, maximum: 3, step: 1, defaultValue: 1, current: 2)
        dev.backlightCompensation = NumericRangeControlState(isSupported: true, canSet: true, minimum: 0, maximum: 8, step: 1, defaultValue: 0, current: 4)
        dev.focusAuto = BooleanControlState(isSupported: true, canSet: true, defaultValue: true, current: false)
        dev.focusAbsolute = NumericRangeControlState(isSupported: true, canSet: true, minimum: 0, maximum: 250, step: 5, defaultValue: 100, current: 85)
        dev.zoomAbsolute = NumericRangeControlState(isSupported: true, canSet: true, minimum: 100, maximum: 400, step: 10, defaultValue: 100, current: 130)
        dev.panAbsolute = NumericRangeControlState(isSupported: true, canSet: true, minimum: -36000, maximum: 36000, step: 3600, defaultValue: 0, current: 7200)
        dev.tiltAbsolute = NumericRangeControlState(isSupported: true, canSet: true, minimum: -36000, maximum: 36000, step: 3600, defaultValue: 0, current: -3600)

        let modes: [UVCStreamResolutionMode] = [
            UVCStreamResolutionMode(
                formatIndex: 1,
                frameIndex: 2,
                codec: .mjpeg,
                width: 2560,
                height: 1440,
                defaultFPS: 30,
                supportedFPS: [10, 15, 24, 30].map { UVCFrameRateOption(fps: $0) }
            ),
            UVCStreamResolutionMode(
                formatIndex: 1,
                frameIndex: 1,
                codec: .mjpeg,
                width: 1920,
                height: 1080,
                defaultFPS: 30,
                supportedFPS: [10, 15, 24, 30, 60].map { UVCFrameRateOption(fps: $0) }
            ),
            UVCStreamResolutionMode(
                formatIndex: 1,
                frameIndex: 3,
                codec: .mjpeg,
                width: 1280,
                height: 720,
                defaultFPS: 30,
                supportedFPS: [15, 24, 30, 60].map { UVCFrameRateOption(fps: $0) }
            ),
            UVCStreamResolutionMode(
                formatIndex: 2,
                frameIndex: 1,
                codec: .uncompressed,
                width: 2560,
                height: 1440,
                defaultFPS: 5,
                supportedFPS: [5, 10].map { UVCFrameRateOption(fps: $0) }
            )
        ]
        dev.streamModes = modes
        dev.defaultStream = UVCStreamValidator.defaultSelection(in: modes)
        dev.selectedStream = UVCStreamValidator.validateSelection(
            modes: modes,
            desiredCodec: .mjpeg,
            desiredWidth: 2560,
            desiredHeight: 1440,
            desiredFPS: 30
        )
        dev.liveHardwareStream = dev.selectedStream
        dev.isHardwareStreamingActive = true
        dev.streamStatusNote = "Active USB stream: 2560×1440 @ 30 fps (MJPEG)"
        dev.lockedTargetSnapshot = dev.captureSnapshot()
        return dev
    }

    public func disconnect() {
        if let h = handle {
            cuvc_close_device(h)
            handle = nil
        }
    }

    public func copyRawConfigurationDescriptor() -> [UInt8]? {
        guard let h = handle else { return nil }
        var buf = [UInt8](repeating: 0, count: 8192)
        var outLen: UInt32 = 0
        if cuvc_copy_config_descriptor(h, &buf, UInt32(buf.count), &outLen), outLen > 0 {
            return Array(buf.prefix(Int(outLen)))
        }
        if outLen > UInt32(buf.count), outLen <= 65536 {
            buf = [UInt8](repeating: 0, count: Int(outLen))
            if cuvc_copy_config_descriptor(h, &buf, UInt32(buf.count), &outLen), outLen > 0 {
                return Array(buf.prefix(Int(outLen)))
            }
        }
        return nil
    }

    public var lastHardwareErrorDescription: String? {
        guard let h = handle else { return nil }
        let code = cuvc_get_last_error(h)
        guard code != 0 else { return nil }
        return DiagnosticsLogger.ioReturnDescription(code)
    }

    deinit {
        if let h = handle {
            cuvc_close_device(h)
        }
    }

    // MARK: - Full Hardware Introspection

    public func refreshAllFromHardware(syncLockedTarget: Bool = false) {
        guard handle != nil else { return }

        // Camera Terminal controls
        autoExposureMode = probeAutoExposureMode()
        autoExposurePriority = probeBoolControl(unit: ctUnit, selector: UInt8(CUVC_CT_AE_PRIORITY_CONTROL.rawValue))
        exposureTime = probeIntControl(unit: ctUnit, selector: UInt8(CUVC_CT_EXPOSURE_TIME_ABSOLUTE_CONTROL.rawValue), bytes: 4, signed: false)
        focusAuto = probeBoolControl(unit: ctUnit, selector: UInt8(CUVC_CT_FOCUS_AUTO_CONTROL.rawValue))
        focusAbsolute = probeIntControl(unit: ctUnit, selector: UInt8(CUVC_CT_FOCUS_ABSOLUTE_CONTROL.rawValue), bytes: 2, signed: false)
        irisAbsolute = probeIntControl(unit: ctUnit, selector: UInt8(CUVC_CT_IRIS_ABSOLUTE_CONTROL.rawValue), bytes: 2, signed: false)
        zoomAbsolute = probeIntControl(unit: ctUnit, selector: UInt8(CUVC_CT_ZOOM_ABSOLUTE_CONTROL.rawValue), bytes: 2, signed: false)
        rollAbsolute = probeIntControl(unit: ctUnit, selector: UInt8(CUVC_CT_ROLL_ABSOLUTE_CONTROL.rawValue), bytes: 2, signed: true)
        scanningMode = probeBoolControl(unit: ctUnit, selector: UInt8(CUVC_CT_SCANNING_MODE_CONTROL.rawValue))
        privacy = probeBoolControl(unit: ctUnit, selector: UInt8(CUVC_CT_PRIVACY_CONTROL.rawValue))
        let (panState, tiltState) = probePanTiltControl()
        panAbsolute = panState
        tiltAbsolute = tiltState

        // Processing Unit controls
        backlightCompensation = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_BACKLIGHT_COMPENSATION_CONTROL.rawValue), bytes: 2, signed: false)
        brightness = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_BRIGHTNESS_CONTROL.rawValue), bytes: 2, signed: true)
        contrast = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_CONTRAST_CONTROL.rawValue), bytes: 2, signed: false)
        contrastAuto = probeBoolControl(unit: puUnit, selector: UInt8(CUVC_PU_CONTRAST_AUTO_CONTROL.rawValue))
        gain = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_GAIN_CONTROL.rawValue), bytes: 2, signed: false)
        powerLineFrequency = probePowerLineFrequency()
        hue = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_HUE_CONTROL.rawValue), bytes: 2, signed: true)
        hueAuto = probeBoolControl(unit: puUnit, selector: UInt8(CUVC_PU_HUE_AUTO_CONTROL.rawValue))
        saturation = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_SATURATION_CONTROL.rawValue), bytes: 2, signed: false)
        sharpness = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_SHARPNESS_CONTROL.rawValue), bytes: 2, signed: false)
        gamma = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_GAMMA_CONTROL.rawValue), bytes: 2, signed: false)
        whiteBalanceAuto = probeBoolControl(unit: puUnit, selector: UInt8(CUVC_PU_WHITE_BALANCE_TEMPERATURE_AUTO_CONTROL.rawValue))
        whiteBalanceTemperature = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_WHITE_BALANCE_TEMPERATURE_CONTROL.rawValue), bytes: 2, signed: false)
        digitalMultiplier = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_DIGITAL_MULTIPLIER_CONTROL.rawValue), bytes: 2, signed: false)

        // UVC VideoStreaming Resolutions & Compatible FPS
        if syncLockedTarget || streamModes.isEmpty {
            probeStreamModes(preserveUserSelection: !syncLockedTarget)
        } else {
            refreshActiveStreamState(preserveUserSelection: true)
        }

        if syncLockedTarget {
            lockedTargetSnapshot = captureSnapshot()
        }
    }

    // MARK: - VideoStreaming Resolution & FPS Introspection / Negotiation

    public var availableStreamCodecs: [UVCVideoCodec] {
        UVCStreamValidator.availableCodecs(in: streamModes)
    }

    public var currentStreamResolutions: [UVCStreamResolutionMode] {
        let codec = selectedStream?.codec ?? availableStreamCodecs.first ?? .mjpeg
        return UVCStreamValidator.resolutions(for: codec, in: streamModes)
    }

    public var currentStreamMode: UVCStreamResolutionMode? {
        guard let sel = selectedStream else { return currentStreamResolutions.first }
        return currentStreamResolutions.first(where: {
            $0.width == sel.width && $0.height == sel.height
        }) ?? currentStreamResolutions.first
    }

    public var availableFPSTiers: [Int] {
        UVCStreamValidator.allFPSTiers(in: streamModes)
    }

    public var isStreamModifiedFromDefault: Bool {
        guard let sel = selectedStream, let def = defaultStream else { return false }
        return sel != def
    }

    public func probeStreamModes(preserveUserSelection: Bool = false) {
        guard let h = handle else {
            streamModes = []
            defaultStream = nil
            selectedStream = nil
            liveHardwareStream = nil
            isHardwareStreamingActive = false
            return
        }

        var rawModes = Array(repeating: CUVCStreamMode(), count: Int(CUVC_MAX_STREAM_MODES))
        let count = Int(cuvc_enumerate_stream_modes(h, &rawModes, Int32(CUVC_MAX_STREAM_MODES)))
        var parsed: [UVCStreamResolutionMode] = []
        if count > 0 {
            for idx in 0..<min(count, rawModes.count) {
                if let m = UVCStreamResolutionMode(cMode: rawModes[idx]) {
                    parsed.append(m)
                }
            }
        }
        streamModes = parsed
        defaultStream = UVCStreamValidator.defaultSelection(in: parsed)
        refreshActiveStreamState(preserveUserSelection: preserveUserSelection)
    }

    public func refreshActiveStreamState(preserveUserSelection: Bool = false) {
        guard let h = handle, !streamModes.isEmpty else { return }
        let vsIfc = selectedStream?.vsInterfaceNumber ?? streamModes.first?.vsInterfaceNumber ?? 1
        var active = CUVCActiveStreamState()
        if cuvc_get_active_stream_state(h, vsIfc, &active), active.isValid {
            isHardwareStreamingActive = active.alternateSetting > 0
            liveHardwareStream = UVCStreamValidator.selectionFromHardwareState(active, in: streamModes)
        } else {
            isHardwareStreamingActive = false
            liveHardwareStream = nil
        }

        if preserveUserSelection, let existing = selectedStream,
           let revalidated = UVCStreamValidator.validateSelection(
               modes: streamModes,
               desiredCodec: existing.codec,
               desiredWidth: existing.width,
               desiredHeight: existing.height,
               desiredFPS: existing.fps
           ) {
            selectedStream = revalidated
        } else {
            selectedStream = liveHardwareStream ?? defaultStream
        }

        if let live = liveHardwareStream {
            if isHardwareStreamingActive {
                streamStatusNote = "Active USB stream: \(live.detailedSummary)"
            } else {
                streamStatusNote = "Hardware USB mode: \(live.detailedSummary)"
            }
        } else if let def = defaultStream {
            streamStatusNote = "Default USB mode: \(def.detailedSummary)"
        }
    }

    @discardableResult
    public func selectStreamCodec(_ codec: UVCVideoCodec) -> Bool {
        let base = selectedStream ?? defaultStream
        let w = base?.width ?? 1920
        let h = base?.height ?? 1080
        let fps = base?.fps ?? 30
        guard let validated = UVCStreamValidator.validateSelection(
            modes: streamModes,
            desiredCodec: codec,
            desiredWidth: w,
            desiredHeight: h,
            desiredFPS: fps
        ) else {
            return false
        }
        return applyStreamSelection(validated)
    }

    @discardableResult
    public func selectStreamResolution(width: Int, height: Int) -> Bool {
        let base = selectedStream ?? defaultStream
        let codec = base?.codec ?? availableStreamCodecs.first ?? .mjpeg
        let fps = base?.fps ?? 30
        guard let validated = UVCStreamValidator.validateSelection(
            modes: streamModes,
            desiredCodec: codec,
            desiredWidth: width,
            desiredHeight: height,
            desiredFPS: fps
        ) else {
            return false
        }
        return applyStreamSelection(validated)
    }

    @discardableResult
    public func selectStreamFPS(_ fps: Int) -> Bool {
        let base = selectedStream ?? defaultStream
        guard let current = base,
              let validated = UVCStreamValidator.validateSelection(
                  modes: streamModes,
                  desiredCodec: current.codec,
                  desiredWidth: current.width,
                  desiredHeight: current.height,
                  desiredFPS: fps
              ) else {
            return false
        }
        return applyStreamSelection(validated)
    }

    @discardableResult
    public func resetStreamToDefault() -> Bool {
        guard let def = defaultStream else { return false }
        return applyStreamSelection(def)
    }

    @discardableResult
    public func applyStreamSelection(_ selection: UVCStreamSelection) -> Bool {
        guard let h = handle, !streamModes.isEmpty else { return false }
        guard let validated = UVCStreamValidator.validateSelection(
            modes: streamModes,
            desiredCodec: selection.codec,
            desiredWidth: selection.width,
            desiredHeight: selection.height,
            desiredFPS: selection.fps
        ) else {
            return false
        }

        var currentActive = CUVCActiveStreamState()
        _ = cuvc_get_active_stream_state(h, validated.vsInterfaceNumber, &currentActive)

        let hostPipeLockedDifferentFrame =
            currentActive.isValid &&
            currentActive.alternateSetting > 0 &&
            (currentActive.formatIndex != validated.formatIndex || currentActive.frameIndex != validated.frameIndex)

        var negotiated = CUVCActiveStreamState()
        if !hostPipeLockedDifferentFrame {
            let ok = cuvc_negotiate_stream_state(
                h,
                validated.vsInterfaceNumber,
                validated.formatIndex,
                validated.frameIndex,
                validated.interval100ns,
                true,
                &negotiated
            )
            guard ok else { return false }
            selectedStream = validated
            liveHardwareStream = validated
            isHardwareStreamingActive = negotiated.alternateSetting > 0
            if isHardwareStreamingActive {
                streamStatusNote = "Live USB stream updated: \(validated.detailedSummary)"
            } else {
                streamStatusNote = "Committed to USB hardware: \(validated.detailedSummary)"
            }
        } else {
            // Host app (e.g. Photo Booth / Zoom) holds an active isochronous pipe locked to another frame size:
            // 1) Stage requested format + resolution + FPS via VS_PROBE_CONTROL without overflowing host buffer
            let probeOk = cuvc_negotiate_stream_state(
                h,
                validated.vsInterfaceNumber,
                validated.formatIndex,
                validated.frameIndex,
                validated.interval100ns,
                false,
                &negotiated
            )
            guard probeOk else { return false }

            // 2) If the active host resolution also supports the chosen FPS, commit the FPS live on the active frame!
            if let activeMode = streamModes.first(where: {
                $0.vsInterfaceNumber == validated.vsInterfaceNumber &&
                $0.formatIndex == currentActive.formatIndex &&
                $0.frameIndex == currentActive.frameIndex
            }), let compatibleOpt = activeMode.option(forFPS: validated.fps) {
                var liveCommit = CUVCActiveStreamState()
                if cuvc_negotiate_stream_state(
                    h,
                    validated.vsInterfaceNumber,
                    currentActive.formatIndex,
                    currentActive.frameIndex,
                    compatibleOpt.interval100ns,
                    true,
                    &liveCommit
                ) {
                    liveHardwareStream = UVCStreamSelection(mode: activeMode, option: compatibleOpt)
                }
            }

            selectedStream = validated
            isHardwareStreamingActive = true
            let liveDesc = liveHardwareStream?.compactSummary ?? "active frame"
            streamStatusNote = "Host app locked \(liveDesc) · Staged \(validated.detailedSummary) on USB Probe"
        }

        lockedTargetSnapshot.streamCodec = validated.codec.rawValue
        lockedTargetSnapshot.streamWidth = validated.width
        lockedTargetSnapshot.streamHeight = validated.height
        lockedTargetSnapshot.streamFPS = validated.fps
        return true
    }

    // MARK: - Low-Level Probing Helpers

    private func probeAutoExposureMode() -> AutoExposureModeState {
        guard let h = handle else { return AutoExposureModeState() }
        let sel = UInt8(CUVC_CT_AE_MODE_CONTROL.rawValue)
        var info: UInt8 = 0
        guard cuvc_get_info(h, ctUnit, sel, &info), info != 0 else {
            return AutoExposureModeState()
        }

        let canSet = (info & UInt8(CUVC_INFO_SUPPORTS_SET.rawValue)) != 0
        var resMask: Int64 = 0
        if !cuvc_get_int(h, UInt8(CUVC_REQ_GET_RES.rawValue), ctUnit, sel, 1, false, &resMask) {
            _ = cuvc_get_int(h, UInt8(CUVC_REQ_GET_MAX.rawValue), ctUnit, sel, 1, false, &resMask)
        }

        var defRaw: Int64 = Int64(AutoExposureMode.aperturePriority.rawValue)
        _ = cuvc_get_int(h, UInt8(CUVC_REQ_GET_DEF.rawValue), ctUnit, sel, 1, false, &defRaw)

        var curRaw: Int64 = defRaw
        _ = cuvc_get_int(h, UInt8(CUVC_REQ_GET_CUR.rawValue), ctUnit, sel, 1, false, &curRaw)

        let supported = AutoExposureMode.supportedModes(fromBitmask: Int(resMask))
        let defMode = AutoExposureMode(rawValue: Int(defRaw)) ?? supported.first ?? .aperturePriority
        let curMode = AutoExposureMode(rawValue: Int(curRaw)) ?? defMode

        return AutoExposureModeState(
            isSupported: true,
            canSet: canSet,
            supportedBitmask: Int(resMask),
            defaultMode: defMode,
            current: curMode
        )
    }

    private func probePowerLineFrequency() -> NumericRangeControlState {
        var state = probeIntControl(unit: puUnit, selector: UInt8(CUVC_PU_POWER_LINE_FREQUENCY_CONTROL.rawValue), bytes: 1, signed: false)
        if state.isSupported && state.maximum <= state.minimum {
            state.minimum = 0
            state.maximum = 2
            state.step = 1
        }
        // "Auto" anti-flicker (value 3) was introduced in UVC 1.5; UVC 1.0/1.1 cameras often stall
        // Endpoint 0 if sent 3 even when GET_MAX reports 3.
        if state.isSupported && identity.uvcVersionBCD > 0 && identity.uvcVersionBCD < 0x0150 {
            state.maximum = min(state.maximum, 2)
        }
        return state
    }

    private func probeBoolControl(unit: UInt8, selector: UInt8) -> BooleanControlState {
        guard let h = handle else { return BooleanControlState() }
        var info: UInt8 = 0
        guard cuvc_get_info(h, unit, selector, &info), info != 0 else {
            return BooleanControlState()
        }
        let canSet = (info & UInt8(CUVC_INFO_SUPPORTS_SET.rawValue)) != 0
        var defVal: Int64 = 0
        let hasDef = cuvc_get_int(h, UInt8(CUVC_REQ_GET_DEF.rawValue), unit, selector, 1, false, &defVal)
        var curVal: Int64 = hasDef ? defVal : 0
        let hasCur = cuvc_get_int(h, UInt8(CUVC_REQ_GET_CUR.rawValue), unit, selector, 1, false, &curVal)
        if !hasCur && !hasDef {
            return BooleanControlState()
        }
        return BooleanControlState(
            isSupported: true,
            canSet: canSet,
            defaultValue: defVal != 0,
            current: curVal != 0
        )
    }

    private func probeIntControl(unit: UInt8, selector: UInt8, bytes: UInt8, signed: Bool) -> NumericRangeControlState {
        guard let h = handle else { return NumericRangeControlState() }
        var info: UInt8 = 0
        guard cuvc_get_info(h, unit, selector, &info), info != 0 else {
            return NumericRangeControlState()
        }

        let canSet = (info & UInt8(CUVC_INFO_SUPPORTS_SET.rawValue)) != 0
        var minVal: Int64 = 0
        var maxVal: Int64 = 0
        let hasMin = cuvc_get_int(h, UInt8(CUVC_REQ_GET_MIN.rawValue), unit, selector, bytes, signed, &minVal)
        let hasMax = cuvc_get_int(h, UInt8(CUVC_REQ_GET_MAX.rawValue), unit, selector, bytes, signed, &maxVal)

        var stepVal: Int64 = 1
        if !cuvc_get_int(h, UInt8(CUVC_REQ_GET_RES.rawValue), unit, selector, bytes, signed, &stepVal) || stepVal <= 0 {
            stepVal = 1
        }

        var defVal: Int64 = hasMin ? minVal : 0
        _ = cuvc_get_int(h, UInt8(CUVC_REQ_GET_DEF.rawValue), unit, selector, bytes, signed, &defVal)

        var curVal: Int64 = defVal
        let hasCur = cuvc_get_int(h, UInt8(CUVC_REQ_GET_CUR.rawValue), unit, selector, bytes, signed, &curVal)

        if !hasMin && !hasMax && !hasCur {
            return NumericRangeControlState()
        }

        return NumericRangeControlState(
            isSupported: true,
            canSet: canSet,
            minimum: Int(minVal),
            maximum: Int(maxVal),
            step: max(1, Int(stepVal)),
            defaultValue: Int(defVal),
            current: Int(curVal)
        )
    }

    private func probePanTiltControl() -> (NumericRangeControlState, NumericRangeControlState) {
        guard let h = handle else { return (NumericRangeControlState(), NumericRangeControlState()) }
        let sel = UInt8(CUVC_CT_PANTILT_ABSOLUTE_CONTROL.rawValue)
        var info: UInt8 = 0
        guard cuvc_get_info(h, ctUnit, sel, &info), info != 0 else {
            return (NumericRangeControlState(), NumericRangeControlState())
        }
        let canSet = (info & UInt8(CUVC_INFO_SUPPORTS_SET.rawValue)) != 0

        var minPan: Int32 = 0, minTilt: Int32 = 0
        var maxPan: Int32 = 0, maxTilt: Int32 = 0
        guard cuvc_get_pantilt(h, UInt8(CUVC_REQ_GET_MIN.rawValue), ctUnit, &minPan, &minTilt),
              cuvc_get_pantilt(h, UInt8(CUVC_REQ_GET_MAX.rawValue), ctUnit, &maxPan, &maxTilt) else {
            return (NumericRangeControlState(), NumericRangeControlState())
        }

        var resPan: Int32 = 3600, resTilt: Int32 = 3600
        if !cuvc_get_pantilt(h, UInt8(CUVC_REQ_GET_RES.rawValue), ctUnit, &resPan, &resTilt) {
            resPan = 3600
            resTilt = 3600
        }
        var defPan: Int32 = 0, defTilt: Int32 = 0
        _ = cuvc_get_pantilt(h, UInt8(CUVC_REQ_GET_DEF.rawValue), ctUnit, &defPan, &defTilt)

        var curPan: Int32 = defPan, curTilt: Int32 = defTilt
        _ = cuvc_get_pantilt(h, UInt8(CUVC_REQ_GET_CUR.rawValue), ctUnit, &curPan, &curTilt)

        let pan = NumericRangeControlState(
            isSupported: true,
            canSet: canSet,
            minimum: Int(minPan),
            maximum: Int(maxPan),
            step: max(1, Int(resPan)),
            defaultValue: Int(defPan),
            current: Int(curPan)
        )
        let tilt = NumericRangeControlState(
            isSupported: true,
            canSet: canSet,
            minimum: Int(minTilt),
            maximum: Int(maxTilt),
            step: max(1, Int(resTilt)),
            defaultValue: Int(defTilt),
            current: Int(curTilt)
        )
        return (pan, tilt)
    }

    // MARK: - Direct Hardware Setters (Live Endpoint 0 Injection)

    @discardableResult
    public func setAutoExposureMode(_ mode: AutoExposureMode) -> Bool {
        guard let h = handle, autoExposureMode.isSupported, autoExposureMode.isModeSupported(mode) else { return false }
        let ok = cuvc_set_int(h, ctUnit, UInt8(CUVC_CT_AE_MODE_CONTROL.rawValue), 1, false, Int64(mode.rawValue))
        if ok {
            autoExposureMode.current = mode
            lockedTargetSnapshot.autoExposureMode = mode.rawValue
            // Read back current exposure time so manual slider starts at exact live shutter value
            var expCur: Int64 = 0
            if exposureTime.isSupported,
               cuvc_get_int(h, UInt8(CUVC_REQ_GET_CUR.rawValue), ctUnit, UInt8(CUVC_CT_EXPOSURE_TIME_ABSOLUTE_CONTROL.rawValue), 4, false, &expCur) {
                exposureTime.current = Int(expCur)
                if mode.allowsManualExposureTime {
                    lockedTargetSnapshot.exposureTime = Int(expCur)
                }
            }
        }
        return ok
    }

    @discardableResult
    public func setAutoExposurePriority(_ enabled: Bool) -> Bool {
        let ok = writeBool(enabled, state: &autoExposurePriority, unit: ctUnit, selector: UInt8(CUVC_CT_AE_PRIORITY_CONTROL.rawValue))
        if ok { lockedTargetSnapshot.autoExposurePriority = enabled ? 1 : 0 }
        return ok
    }

    @discardableResult
    public func setExposureTime(_ value: Int) -> Bool {
        guard autoExposureMode.allowsManualExposureTime else { return false }
        let ok = writeInt(value, state: &exposureTime, unit: ctUnit, selector: UInt8(CUVC_CT_EXPOSURE_TIME_ABSOLUTE_CONTROL.rawValue), bytes: 4, signed: false)
        if ok { lockedTargetSnapshot.exposureTime = exposureTime.current }
        return ok
    }

    @discardableResult
    public func setGain(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &gain, unit: puUnit, selector: UInt8(CUVC_PU_GAIN_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.gain = gain.current }
        return ok
    }

    @discardableResult
    public func setBrightness(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &brightness, unit: puUnit, selector: UInt8(CUVC_PU_BRIGHTNESS_CONTROL.rawValue), bytes: 2, signed: true)
        if ok { lockedTargetSnapshot.brightness = brightness.current }
        return ok
    }

    @discardableResult
    public func setContrastAuto(_ enabled: Bool) -> Bool {
        let ok = writeBool(enabled, state: &contrastAuto, unit: puUnit, selector: UInt8(CUVC_PU_CONTRAST_AUTO_CONTROL.rawValue))
        if ok { lockedTargetSnapshot.contrastAuto = enabled }
        return ok
    }

    @discardableResult
    public func setContrast(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &contrast, unit: puUnit, selector: UInt8(CUVC_PU_CONTRAST_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.contrast = contrast.current }
        return ok
    }

    @discardableResult
    public func setHueAuto(_ enabled: Bool) -> Bool {
        let ok = writeBool(enabled, state: &hueAuto, unit: puUnit, selector: UInt8(CUVC_PU_HUE_AUTO_CONTROL.rawValue))
        if ok { lockedTargetSnapshot.hueAuto = enabled }
        return ok
    }

    @discardableResult
    public func setHue(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &hue, unit: puUnit, selector: UInt8(CUVC_PU_HUE_CONTROL.rawValue), bytes: 2, signed: true)
        if ok { lockedTargetSnapshot.hue = hue.current }
        return ok
    }

    @discardableResult
    public func setSaturation(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &saturation, unit: puUnit, selector: UInt8(CUVC_PU_SATURATION_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.saturation = saturation.current }
        return ok
    }

    @discardableResult
    public func setSharpness(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &sharpness, unit: puUnit, selector: UInt8(CUVC_PU_SHARPNESS_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.sharpness = sharpness.current }
        return ok
    }

    @discardableResult
    public func setGamma(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &gamma, unit: puUnit, selector: UInt8(CUVC_PU_GAMMA_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.gamma = gamma.current }
        return ok
    }

    @discardableResult
    public func setWhiteBalanceAuto(_ enabled: Bool) -> Bool {
        let ok = writeBool(enabled, state: &whiteBalanceAuto, unit: puUnit, selector: UInt8(CUVC_PU_WHITE_BALANCE_TEMPERATURE_AUTO_CONTROL.rawValue))
        if ok {
            lockedTargetSnapshot.whiteBalanceAuto = enabled
            if let h = handle, whiteBalanceTemperature.isSupported {
                var curKelvin: Int64 = 0
                if cuvc_get_int(h, UInt8(CUVC_REQ_GET_CUR.rawValue), puUnit, UInt8(CUVC_PU_WHITE_BALANCE_TEMPERATURE_CONTROL.rawValue), 2, false, &curKelvin) {
                    whiteBalanceTemperature.current = Int(curKelvin)
                    if !enabled {
                        lockedTargetSnapshot.whiteBalanceTemperature = Int(curKelvin)
                    }
                }
            }
        }
        return ok
    }

    @discardableResult
    public func setWhiteBalanceTemperature(_ value: Int) -> Bool {
        if whiteBalanceAuto.isSupported && whiteBalanceAuto.current {
            return false
        }
        let ok = writeInt(value, state: &whiteBalanceTemperature, unit: puUnit, selector: UInt8(CUVC_PU_WHITE_BALANCE_TEMPERATURE_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.whiteBalanceTemperature = whiteBalanceTemperature.current }
        return ok
    }

    @discardableResult
    public func setPowerLineFrequency(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &powerLineFrequency, unit: puUnit, selector: UInt8(CUVC_PU_POWER_LINE_FREQUENCY_CONTROL.rawValue), bytes: 1, signed: false)
        if ok { lockedTargetSnapshot.powerLineFrequency = powerLineFrequency.current }
        return ok
    }

    @discardableResult
    public func setBacklightCompensation(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &backlightCompensation, unit: puUnit, selector: UInt8(CUVC_PU_BACKLIGHT_COMPENSATION_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.backlightCompensation = backlightCompensation.current }
        return ok
    }

    @discardableResult
    public func setBacklightEnabled(_ enabled: Bool) -> Bool {
        guard backlightCompensation.isSupported else { return false }
        if !enabled {
            return setBacklightCompensation(backlightCompensation.minimum)
        } else {
            let activeVal = backlightCompensation.defaultValue > backlightCompensation.minimum
                ? backlightCompensation.defaultValue
                : backlightCompensation.maximum
            return setBacklightCompensation(activeVal)
        }
    }

    @discardableResult
    public func setFocusAuto(_ enabled: Bool) -> Bool {
        let ok = writeBool(enabled, state: &focusAuto, unit: ctUnit, selector: UInt8(CUVC_CT_FOCUS_AUTO_CONTROL.rawValue))
        if ok {
            lockedTargetSnapshot.focusAuto = enabled
            if let h = handle, focusAbsolute.isSupported {
                var curFocus: Int64 = 0
                if cuvc_get_int(h, UInt8(CUVC_REQ_GET_CUR.rawValue), ctUnit, UInt8(CUVC_CT_FOCUS_ABSOLUTE_CONTROL.rawValue), 2, false, &curFocus) {
                    focusAbsolute.current = Int(curFocus)
                    if !enabled {
                        lockedTargetSnapshot.focusAbsolute = Int(curFocus)
                    }
                }
            }
        }
        return ok
    }

    @discardableResult
    public func setFocusAbsolute(_ value: Int) -> Bool {
        if focusAuto.isSupported && focusAuto.current {
            return false
        }
        let ok = writeInt(value, state: &focusAbsolute, unit: ctUnit, selector: UInt8(CUVC_CT_FOCUS_ABSOLUTE_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.focusAbsolute = focusAbsolute.current }
        return ok
    }

    @discardableResult
    public func setZoomAbsolute(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &zoomAbsolute, unit: ctUnit, selector: UInt8(CUVC_CT_ZOOM_ABSOLUTE_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.zoomAbsolute = zoomAbsolute.current }
        return ok
    }

    @discardableResult
    public func setDigitalMultiplier(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &digitalMultiplier, unit: puUnit, selector: UInt8(CUVC_PU_DIGITAL_MULTIPLIER_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.digitalMultiplier = digitalMultiplier.current }
        return ok
    }

    @discardableResult
    public func setPanAbsolute(_ value: Int) -> Bool {
        guard let h = handle, panAbsolute.isSupported else { return false }
        let snappedPan = panAbsolute.clampedAndSnapped(value)
        let ok = cuvc_set_pantilt(h, ctUnit, Int32(snappedPan), Int32(tiltAbsolute.current))
        if ok {
            panAbsolute.current = snappedPan
            lockedTargetSnapshot.panAbsolute = snappedPan
        }
        return ok
    }

    @discardableResult
    public func setTiltAbsolute(_ value: Int) -> Bool {
        guard let h = handle, tiltAbsolute.isSupported else { return false }
        let snappedTilt = tiltAbsolute.clampedAndSnapped(value)
        let ok = cuvc_set_pantilt(h, ctUnit, Int32(panAbsolute.current), Int32(snappedTilt))
        if ok {
            tiltAbsolute.current = snappedTilt
            lockedTargetSnapshot.tiltAbsolute = snappedTilt
        }
        return ok
    }

    @discardableResult
    public func setIrisAbsolute(_ value: Int) -> Bool {
        guard autoExposureMode.allowsManualIris else { return false }
        let ok = writeInt(value, state: &irisAbsolute, unit: ctUnit, selector: UInt8(CUVC_CT_IRIS_ABSOLUTE_CONTROL.rawValue), bytes: 2, signed: false)
        if ok { lockedTargetSnapshot.irisAbsolute = irisAbsolute.current }
        return ok
    }

    @discardableResult
    public func setRollAbsolute(_ value: Int) -> Bool {
        let ok = writeInt(value, state: &rollAbsolute, unit: ctUnit, selector: UInt8(CUVC_CT_ROLL_ABSOLUTE_CONTROL.rawValue), bytes: 2, signed: true)
        if ok { lockedTargetSnapshot.rollAbsolute = rollAbsolute.current }
        return ok
    }

    @discardableResult
    public func setScanningMode(_ progressive: Bool) -> Bool {
        let ok = writeBool(progressive, state: &scanningMode, unit: ctUnit, selector: UInt8(CUVC_CT_SCANNING_MODE_CONTROL.rawValue))
        if ok { lockedTargetSnapshot.scanningMode = progressive }
        return ok
    }

    @discardableResult
    public func setPrivacy(_ closed: Bool) -> Bool {
        let ok = writeBool(closed, state: &privacy, unit: ctUnit, selector: UInt8(CUVC_CT_PRIVACY_CONTROL.rawValue))
        if ok { lockedTargetSnapshot.privacy = closed }
        return ok
    }

    // MARK: - Private Write Primitives

    private func writeInt(
        _ rawValue: Int,
        state: inout NumericRangeControlState,
        unit: UInt8,
        selector: UInt8,
        bytes: UInt8,
        signed: Bool
    ) -> Bool {
        guard let h = handle, state.isSupported, state.canSet else { return false }
        let snapped = state.clampedAndSnapped(rawValue)
        let ok = cuvc_set_int(h, unit, selector, bytes, signed, Int64(snapped))
        if ok {
            state.current = snapped
        }
        return ok
    }

    private func writeBool(
        _ value: Bool,
        state: inout BooleanControlState,
        unit: UInt8,
        selector: UInt8
    ) -> Bool {
        guard let h = handle, state.isSupported, state.canSet else { return false }
        let ok = cuvc_set_int(h, unit, selector, 1, false, value ? 1 : 0)
        if ok {
            state.current = value
        }
        return ok
    }

    // MARK: - Presets, Factory Defaults & Anti-Reset Lock

    public func captureSnapshot() -> CameraSettingsSnapshot {
        CameraSettingsSnapshot(
            autoExposureMode: autoExposureMode.isSupported ? autoExposureMode.current.rawValue : nil,
            autoExposurePriority: autoExposurePriority.isSupported ? (autoExposurePriority.current ? 1 : 0) : nil,
            exposureTime: exposureTime.isSupported ? exposureTime.current : nil,
            gain: gain.isSupported ? gain.current : nil,
            brightness: brightness.isSupported ? brightness.current : nil,
            contrast: contrast.isSupported ? contrast.current : nil,
            contrastAuto: contrastAuto.isSupported ? contrastAuto.current : nil,
            hue: hue.isSupported ? hue.current : nil,
            hueAuto: hueAuto.isSupported ? hueAuto.current : nil,
            saturation: saturation.isSupported ? saturation.current : nil,
            sharpness: sharpness.isSupported ? sharpness.current : nil,
            gamma: gamma.isSupported ? gamma.current : nil,
            whiteBalanceAuto: whiteBalanceAuto.isSupported ? whiteBalanceAuto.current : nil,
            whiteBalanceTemperature: whiteBalanceTemperature.isSupported ? whiteBalanceTemperature.current : nil,
            powerLineFrequency: powerLineFrequency.isSupported ? powerLineFrequency.current : nil,
            backlightCompensation: backlightCompensation.isSupported ? backlightCompensation.current : nil,
            focusAuto: focusAuto.isSupported ? focusAuto.current : nil,
            focusAbsolute: focusAbsolute.isSupported ? focusAbsolute.current : nil,
            zoomAbsolute: zoomAbsolute.isSupported ? zoomAbsolute.current : nil,
            digitalMultiplier: digitalMultiplier.isSupported ? digitalMultiplier.current : nil,
            panAbsolute: panAbsolute.isSupported ? panAbsolute.current : nil,
            tiltAbsolute: tiltAbsolute.isSupported ? tiltAbsolute.current : nil,
            irisAbsolute: irisAbsolute.isSupported ? irisAbsolute.current : nil,
            rollAbsolute: rollAbsolute.isSupported ? rollAbsolute.current : nil,
            scanningMode: scanningMode.isSupported ? scanningMode.current : nil,
            privacy: privacy.isSupported ? privacy.current : nil,
            streamCodec: selectedStream?.codec.rawValue,
            streamWidth: selectedStream?.width,
            streamHeight: selectedStream?.height,
            streamFPS: selectedStream?.fps
        )
    }

    public func applySnapshot(_ snapshot: CameraSettingsSnapshot) {
        // If snapshot saves both a manual register AND an Auto mode ON, unlock temporarily to write manual shadow register cleanly
        if let exp = snapshot.exposureTime,
           let aeRaw = snapshot.autoExposureMode,
           let targetMode = AutoExposureMode(rawValue: aeRaw),
           !targetMode.allowsManualExposureTime,
           autoExposureMode.isModeSupported(.manual) {
            _ = setAutoExposureMode(.manual)
            usleep(4_000)
            _ = setExposureTime(exp)
        }

        if let wbTemp = snapshot.whiteBalanceTemperature,
           snapshot.whiteBalanceAuto == true,
           whiteBalanceAuto.isSupported {
            _ = setWhiteBalanceAuto(false)
            usleep(4_000)
            _ = setWhiteBalanceTemperature(wbTemp)
        }

        // 1. Apply mode/auto switches FIRST so manual registers are unlocked on the sensor ISP
        if let aeRaw = snapshot.autoExposureMode, let mode = AutoExposureMode(rawValue: aeRaw) {
            _ = setAutoExposureMode(mode)
        }
        if let aePrio = snapshot.autoExposurePriority {
            _ = setAutoExposurePriority(aePrio != 0)
        }
        if let wbAuto = snapshot.whiteBalanceAuto {
            _ = setWhiteBalanceAuto(wbAuto)
        }
        if let fAuto = snapshot.focusAuto {
            _ = setFocusAuto(fAuto)
        }
        if let cAuto = snapshot.contrastAuto {
            _ = setContrastAuto(cAuto)
        }
        if let hAuto = snapshot.hueAuto {
            _ = setHueAuto(hAuto)
        }

        // Brief 5ms microcontroller state-machine settle when switching out of Auto mode
        usleep(5_000)

        // 2. Apply manual numeric registers
        if let exp = snapshot.exposureTime, autoExposureMode.allowsManualExposureTime {
            _ = setExposureTime(exp)
        }
        if let g = snapshot.gain { _ = setGain(g) }
        if let b = snapshot.brightness { _ = setBrightness(b) }
        if let c = snapshot.contrast, !(contrastAuto.isSupported && contrastAuto.current) {
            _ = setContrast(c)
        }
        if let h = snapshot.hue, !(hueAuto.isSupported && hueAuto.current) {
            _ = setHue(h)
        }
        if let s = snapshot.saturation { _ = setSaturation(s) }
        if let sh = snapshot.sharpness { _ = setSharpness(sh) }
        if let gm = snapshot.gamma { _ = setGamma(gm) }
        if let wbTemp = snapshot.whiteBalanceTemperature, !(whiteBalanceAuto.isSupported && whiteBalanceAuto.current) {
            _ = setWhiteBalanceTemperature(wbTemp)
        }
        if let plf = snapshot.powerLineFrequency { _ = setPowerLineFrequency(plf) }
        if let blc = snapshot.backlightCompensation { _ = setBacklightCompensation(blc) }
        if let fAbs = snapshot.focusAbsolute, !(focusAuto.isSupported && focusAuto.current) {
            _ = setFocusAbsolute(fAbs)
        }
        if let zAbs = snapshot.zoomAbsolute { _ = setZoomAbsolute(zAbs) }
        if let dMult = snapshot.digitalMultiplier { _ = setDigitalMultiplier(dMult) }
        if let pAbs = snapshot.panAbsolute { _ = setPanAbsolute(pAbs) }
        if let tAbs = snapshot.tiltAbsolute { _ = setTiltAbsolute(tAbs) }
        if let iAbs = snapshot.irisAbsolute, autoExposureMode.allowsManualIris {
            _ = setIrisAbsolute(iAbs)
        }
        if let rAbs = snapshot.rollAbsolute { _ = setRollAbsolute(rAbs) }
        if let scan = snapshot.scanningMode { _ = setScanningMode(scan) }
        if let priv = snapshot.privacy { _ = setPrivacy(priv) }

        if let codecRaw = snapshot.streamCodec,
           let codec = UVCVideoCodec(rawValue: codecRaw),
           let w = snapshot.streamWidth,
           let h = snapshot.streamHeight,
           let fps = snapshot.streamFPS,
           let validated = UVCStreamValidator.validateSelection(
               modes: streamModes,
               desiredCodec: codec,
               desiredWidth: w,
               desiredHeight: h,
               desiredFPS: fps
           ) {
            _ = applyStreamSelection(validated)
        }

        lockedTargetSnapshot = captureSnapshot()
    }

    public func resetAllToHardwareDefaults() {
        _ = resetStreamToDefault()

        // Set manual modes temporarily where needed so default manual registers can also be written cleanly,
        // then restore default Auto modes.
        if autoExposureMode.isSupported {
            if autoExposureMode.isModeSupported(.manual) {
                _ = setAutoExposureMode(.manual)
                usleep(4_000)
                if exposureTime.isSupported { _ = setExposureTime(exposureTime.defaultValue) }
                if irisAbsolute.isSupported { _ = setIrisAbsolute(irisAbsolute.defaultValue) }
            }
            _ = setAutoExposureMode(autoExposureMode.defaultMode)
        }
        if autoExposurePriority.isSupported { _ = setAutoExposurePriority(autoExposurePriority.defaultValue) }
        if gain.isSupported { _ = setGain(gain.defaultValue) }
        if brightness.isSupported { _ = setBrightness(brightness.defaultValue) }
        if contrastAuto.isSupported { _ = setContrastAuto(contrastAuto.defaultValue) }
        if contrast.isSupported { _ = setContrast(contrast.defaultValue) }
        if hueAuto.isSupported { _ = setHueAuto(hueAuto.defaultValue) }
        if hue.isSupported { _ = setHue(hue.defaultValue) }
        if saturation.isSupported { _ = setSaturation(saturation.defaultValue) }
        if sharpness.isSupported { _ = setSharpness(sharpness.defaultValue) }
        if gamma.isSupported { _ = setGamma(gamma.defaultValue) }

        if whiteBalanceAuto.isSupported {
            _ = setWhiteBalanceAuto(false)
            usleep(4_000)
            if whiteBalanceTemperature.isSupported {
                _ = setWhiteBalanceTemperature(whiteBalanceTemperature.defaultValue)
            }
            _ = setWhiteBalanceAuto(whiteBalanceAuto.defaultValue)
        } else if whiteBalanceTemperature.isSupported {
            _ = setWhiteBalanceTemperature(whiteBalanceTemperature.defaultValue)
        }

        if powerLineFrequency.isSupported { _ = setPowerLineFrequency(powerLineFrequency.defaultValue) }
        if backlightCompensation.isSupported { _ = setBacklightCompensation(backlightCompensation.defaultValue) }

        if focusAuto.isSupported {
            _ = setFocusAuto(false)
            usleep(4_000)
            if focusAbsolute.isSupported { _ = setFocusAbsolute(focusAbsolute.defaultValue) }
            _ = setFocusAuto(focusAuto.defaultValue)
        } else if focusAbsolute.isSupported {
            _ = setFocusAbsolute(focusAbsolute.defaultValue)
        }

        if zoomAbsolute.isSupported { _ = setZoomAbsolute(zoomAbsolute.defaultValue) }
        if digitalMultiplier.isSupported { _ = setDigitalMultiplier(digitalMultiplier.defaultValue) }
        if panAbsolute.isSupported { _ = setPanAbsolute(panAbsolute.defaultValue) }
        if tiltAbsolute.isSupported { _ = setTiltAbsolute(tiltAbsolute.defaultValue) }
        if rollAbsolute.isSupported { _ = setRollAbsolute(rollAbsolute.defaultValue) }
        if scanningMode.isSupported { _ = setScanningMode(scanningMode.defaultValue) }
        if privacy.isSupported { _ = setPrivacy(privacy.defaultValue) }

        refreshAllFromHardware(syncLockedTarget: true)
    }

    /// Checks live hardware registers against `lockedTargetSnapshot` and re-injects any drifted values
    /// (for instance when Zoom/Teams/Photo Booth resets camera registers on stream start).
    @discardableResult
    public func enforceLockedSnapshotIfDrifted() -> Int {
        guard handle != nil else { return 0 }
        let target = lockedTargetSnapshot
        refreshAllFromHardware(syncLockedTarget: false)

        var restoredCount = 0

        if let aeRaw = target.autoExposureMode,
           autoExposureMode.isSupported,
           autoExposureMode.current.rawValue != aeRaw,
           let mode = AutoExposureMode(rawValue: aeRaw) {
            if setAutoExposureMode(mode) { restoredCount += 1 }
            usleep(4_000)
        }

        if let aePrio = target.autoExposurePriority,
           autoExposurePriority.isSupported,
           autoExposurePriority.current != (aePrio != 0) {
            if setAutoExposurePriority(aePrio != 0) { restoredCount += 1 }
        }

        if let wbAuto = target.whiteBalanceAuto,
           whiteBalanceAuto.isSupported,
           whiteBalanceAuto.current != wbAuto {
            if setWhiteBalanceAuto(wbAuto) { restoredCount += 1 }
            usleep(4_000)
        }

        if let fAuto = target.focusAuto,
           focusAuto.isSupported,
           focusAuto.current != fAuto {
            if setFocusAuto(fAuto) { restoredCount += 1 }
            usleep(4_000)
        }

        if let exp = target.exposureTime,
           exposureTime.isSupported,
           autoExposureMode.allowsManualExposureTime,
           exposureTime.current != exp {
            if setExposureTime(exp) { restoredCount += 1 }
        }

        if let g = target.gain, gain.isSupported, gain.current != g {
            if setGain(g) { restoredCount += 1 }
        }
        if let b = target.brightness, brightness.isSupported, brightness.current != b {
            if setBrightness(b) { restoredCount += 1 }
        }
        if let c = target.contrast, contrast.isSupported, contrast.current != c {
            if setContrast(c) { restoredCount += 1 }
        }
        if let h = target.hue, hue.isSupported, hue.current != h {
            if setHue(h) { restoredCount += 1 }
        }
        if let s = target.saturation, saturation.isSupported, saturation.current != s {
            if setSaturation(s) { restoredCount += 1 }
        }
        if let sh = target.sharpness, sharpness.isSupported, sharpness.current != sh {
            if setSharpness(sh) { restoredCount += 1 }
        }
        if let gm = target.gamma, gamma.isSupported, gamma.current != gm {
            if setGamma(gm) { restoredCount += 1 }
        }
        if let wbTemp = target.whiteBalanceTemperature,
           whiteBalanceTemperature.isSupported,
           !(whiteBalanceAuto.isSupported && whiteBalanceAuto.current),
           whiteBalanceTemperature.current != wbTemp {
            if setWhiteBalanceTemperature(wbTemp) { restoredCount += 1 }
        }
        if let plf = target.powerLineFrequency, powerLineFrequency.isSupported, powerLineFrequency.current != plf {
            if setPowerLineFrequency(plf) { restoredCount += 1 }
        }
        if let blc = target.backlightCompensation, backlightCompensation.isSupported, backlightCompensation.current != blc {
            if setBacklightCompensation(blc) { restoredCount += 1 }
        }
        if let fAbs = target.focusAbsolute,
           focusAbsolute.isSupported,
           !(focusAuto.isSupported && focusAuto.current),
           focusAbsolute.current != fAbs {
            if setFocusAbsolute(fAbs) { restoredCount += 1 }
        }
        if let zAbs = target.zoomAbsolute, zoomAbsolute.isSupported, zoomAbsolute.current != zAbs {
            if setZoomAbsolute(zAbs) { restoredCount += 1 }
        }
        if let pAbs = target.panAbsolute, panAbsolute.isSupported, panAbsolute.current != pAbs {
            if setPanAbsolute(pAbs) { restoredCount += 1 }
        }
        if let tAbs = target.tiltAbsolute, tiltAbsolute.isSupported, tiltAbsolute.current != tAbs {
            if setTiltAbsolute(tAbs) { restoredCount += 1 }
        }

        lockedTargetSnapshot = target
        return restoredCount
    }
}
