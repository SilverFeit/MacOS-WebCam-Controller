import SwiftUI
import UVCCore

public struct AdvancedTabView: View {
    @ObservedObject var camera: UVCCameraDevice

    public init(camera: UVCCameraDevice) {
        self.camera = camera
    }

    private var activeZoomState: NumericRangeControlState {
        camera.zoomAbsolute.isSupported ? camera.zoomAbsolute : camera.digitalMultiplier
    }

    private var isBacklightOn: Bool {
        camera.backlightCompensation.isSupported &&
        camera.backlightCompensation.current > camera.backlightCompensation.minimum
    }

    private var defaultBacklightOn: Bool {
        camera.backlightCompensation.isSupported &&
        camera.backlightCompensation.defaultValue > camera.backlightCompensation.minimum
    }

    private var powerLineTitle: String {
        guard camera.powerLineFrequency.isSupported else { return "N/A" }
        return PowerLineFrequency(rawValue: camera.powerLineFrequency.current)?.title ?? "\(camera.powerLineFrequency.current)"
    }

    private var powerLineDefaultTitle: String {
        PowerLineFrequency(rawValue: camera.powerLineFrequency.defaultValue)?.title ?? "\(camera.powerLineFrequency.defaultValue)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // 0. Video Resolution & Compatible FPS (UVC VideoStreaming Hardware Introspection)
            videoStreamSection

            // 1. Power Line Frequency (anti-flicker) - Matches screenshot right panel + Rollback
            PanelGroupBox(
                "Power Line Frequency (anti-flicker)",
                headerTrailing: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                            .opacity(camera.powerLineFrequency.isSupported ? 0.9 : 0.35)

                        RollbackIconButton(
                            isEnabled: camera.powerLineFrequency.isSupported && camera.powerLineFrequency.canSet,
                            isModified: camera.powerLineFrequency.isSupported &&
                                camera.powerLineFrequency.current != camera.powerLineFrequency.defaultValue,
                            helpText: "Rollback Power Line Frequency to default (\(powerLineDefaultTitle))"
                        ) {
                            _ = camera.setPowerLineFrequency(camera.powerLineFrequency.defaultValue)
                        }

                        Text(powerLineTitle)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(
                                !camera.powerLineFrequency.isSupported ? Color.secondary.opacity(0.4) :
                                (camera.powerLineFrequency.current == camera.powerLineFrequency.defaultValue ? Color.secondary : Color.accentColor)
                            )
                    }
                }
            ) {
                HardwareSegmentedBar(
                    options: PowerLineFrequency.allCases.map { freq in
                        let maxSupported = camera.powerLineFrequency.maximum
                        let enabled = freq.rawValue >= camera.powerLineFrequency.minimum && freq.rawValue <= maxSupported
                        return SegmentedOptionItem(id: freq.rawValue, title: freq.title, isEnabled: enabled)
                    },
                    selectedID: camera.powerLineFrequency.current,
                    isControlSupported: camera.powerLineFrequency.isSupported
                ) { selectedRaw in
                    _ = camera.setPowerLineFrequency(selectedRaw)
                }
            }

            // 2. Backlight Compensation - Matches screenshot [Off | On] + Rollback + multi-step Level slider
            PanelGroupBox("Backlight Compensation") {
                HStack(spacing: 6) {
                    Text("#")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Image(systemName: "person.crop.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    HardwareSegmentedBar(
                        options: [
                            SegmentedOptionItem(id: false, title: "Off"),
                            SegmentedOptionItem(id: true, title: "On")
                        ],
                        selectedID: isBacklightOn,
                        isControlSupported: camera.backlightCompensation.isSupported
                    ) { turnOn in
                        _ = camera.setBacklightEnabled(turnOn)
                    }

                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isBacklightOn ? Color.accentColor : Color.secondary)

                    RollbackIconButton(
                        isEnabled: camera.backlightCompensation.isSupported && camera.backlightCompensation.canSet,
                        isModified: camera.backlightCompensation.isSupported &&
                            camera.backlightCompensation.current != camera.backlightCompensation.defaultValue,
                        helpText: "Rollback Backlight Compensation to default (\(defaultBacklightOn ? "On" : "Off"), level \(camera.backlightCompensation.defaultValue))"
                    ) {
                        _ = camera.setBacklightCompensation(camera.backlightCompensation.defaultValue)
                    }

                    Text(!camera.backlightCompensation.isSupported ? "N/A" : (isBacklightOn ? "On" : "Off"))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(
                            !camera.backlightCompensation.isSupported ? Color.secondary.opacity(0.4) :
                            (isBacklightOn == defaultBacklightOn ? Color.secondary : Color.accentColor)
                        )
                        .frame(minWidth: 32, alignment: .trailing)
                }

                // Multi-level fine slider when camera hardware supports > 1 step (e.g. Creative Live! Cam Sync V3: 0..8)
                if camera.backlightCompensation.isSupported &&
                    (camera.backlightCompensation.maximum - camera.backlightCompensation.minimum) > 1 {
                    PanelSliderRow(
                        label: "Level",
                        labelWidth: 52,
                        state: camera.backlightCompensation,
                        leftIcon: {
                            Image(systemName: "circle.dotted")
                                .font(.system(size: 11))
                        },
                        rightIcon: {
                            Image(systemName: "sun.haze.fill")
                                .font(.system(size: 11))
                        }
                    ) { newLevel in
                        _ = camera.setBacklightCompensation(newLevel)
                    }
                }
            }

            // 3. Low Light Compensation (AE Priority) - Standard Windows UVC Camera Control option + Rollback
            PanelGroupBox("Low Light Compensation (AE Priority)") {
                HStack(spacing: 6) {
                    Image(systemName: "video.badge.waveform")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    HardwareSegmentedBar(
                        options: [
                            SegmentedOptionItem(id: false, title: "Off (Constant FPS)"),
                            SegmentedOptionItem(id: true, title: "On (Auto Low-Light)")
                        ],
                        selectedID: camera.autoExposurePriority.current,
                        isControlSupported: camera.autoExposurePriority.isSupported,
                        compact: true
                    ) { enabled in
                        _ = camera.setAutoExposurePriority(enabled)
                    }

                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(
                            camera.autoExposurePriority.isSupported && camera.autoExposurePriority.current
                            ? Color.accentColor
                            : Color.secondary
                        )
                        .opacity(camera.autoExposurePriority.isSupported ? 0.9 : 0.35)

                    RollbackIconButton(
                        isEnabled: camera.autoExposurePriority.isSupported && camera.autoExposurePriority.canSet,
                        isModified: camera.autoExposurePriority.isSupported &&
                            camera.autoExposurePriority.current != camera.autoExposurePriority.defaultValue,
                        helpText: "Rollback Low Light Compensation to default (\(camera.autoExposurePriority.defaultValue ? "On" : "Off"))"
                    ) {
                        _ = camera.setAutoExposurePriority(camera.autoExposurePriority.defaultValue)
                    }

                    Text(!camera.autoExposurePriority.isSupported ? "N/A" : (camera.autoExposurePriority.current ? "On" : "Off"))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(
                            !camera.autoExposurePriority.isSupported ? Color.secondary.opacity(0.4) :
                            (camera.autoExposurePriority.current == camera.autoExposurePriority.defaultValue ? Color.secondary : Color.accentColor)
                        )
                        .frame(minWidth: 32, alignment: .trailing)
                }
            }

            // 4. Focus - Matches screenshot [Auto] # [-] ----o---- [+] [↺] [Value]
            PanelGroupBox(
                "Focus",
                headerTrailing: {
                    if camera.focusAuto.isSupported {
                        HStack(spacing: 5) {
                            Image(systemName: "scope")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)

                            RollbackIconButton(
                                isEnabled: camera.focusAuto.canSet,
                                isModified: camera.focusAuto.current != camera.focusAuto.defaultValue,
                                helpText: "Rollback Auto-Focus mode to default (\(camera.focusAuto.defaultValue ? "Auto" : "Manual"))"
                            ) {
                                _ = camera.setFocusAuto(camera.focusAuto.defaultValue)
                            }

                            Text(camera.focusAuto.current ? "Auto" : "Manual")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(
                                    camera.focusAuto.current == camera.focusAuto.defaultValue
                                    ? Color.secondary
                                    : Color.accentColor
                                )
                        }
                    }
                }
            ) {
                HStack(spacing: 8) {
                    Toggle(
                        "Auto",
                        isOn: Binding(
                            get: { camera.focusAuto.current },
                            set: { _ = camera.setFocusAuto($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .disabled(!camera.focusAuto.isSupported)

                    Text("#")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    PanelSliderRow(
                        label: "",
                        labelWidth: 0,
                        state: camera.focusAbsolute,
                        isLockedByAuto: camera.focusAuto.isSupported && camera.focusAuto.current,
                        leftIcon: {
                            Image(systemName: "minus.square")
                                .font(.system(size: 13))
                        },
                        rightIcon: {
                            Image(systemName: "plus.square")
                                .font(.system(size: 13))
                        }
                    ) { newFocus in
                        _ = camera.setFocusAbsolute(newFocus)
                    }
                }
            }

            // 5. PTZ & Optical Controls (Zoom, Pan, Tilt + Windows UVC Iris/Roll/Privacy)
            VStack(alignment: .leading, spacing: 8) {
                PanelSliderRow(
                    label: "Zoom",
                    labelWidth: 68,
                    state: activeZoomState,
                    formattedValue: activeZoomState.isSupported ? activeZoomState.formattedZoomShort : nil,
                    leftIcon: {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 12))
                    },
                    rightIcon: {
                        Image(systemName: "person.fill.viewfinder")
                            .font(.system(size: 12))
                    }
                ) { newZoom in
                    if camera.zoomAbsolute.isSupported {
                        _ = camera.setZoomAbsolute(newZoom)
                    } else if camera.digitalMultiplier.isSupported {
                        _ = camera.setDigitalMultiplier(newZoom)
                    }
                }

                PanelSliderRow(
                    label: "Pan",
                    labelWidth: 68,
                    state: camera.panAbsolute,
                    formattedValue: camera.panAbsolute.isSupported ? camera.panAbsolute.formattedArcsecondsDegrees : nil,
                    leftIcon: {
                        Image(systemName: "arrow.left.to.line")
                            .font(.system(size: 12))
                    },
                    rightIcon: {
                        Image(systemName: "arrow.right.to.line")
                            .font(.system(size: 12))
                    }
                ) { _ = camera.setPanAbsolute($0) }

                PanelSliderRow(
                    label: "Tilt",
                    labelWidth: 68,
                    state: camera.tiltAbsolute,
                    formattedValue: camera.tiltAbsolute.isSupported ? camera.tiltAbsolute.formattedArcsecondsDegrees : nil,
                    leftIcon: {
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 12))
                    },
                    rightIcon: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 12))
                    }
                ) { _ = camera.setTiltAbsolute($0) }

                if camera.irisAbsolute.isSupported {
                    PanelSliderRow(
                        label: "Aperture",
                        labelWidth: 68,
                        state: camera.irisAbsolute,
                        isLockedByAuto: !camera.autoExposureMode.allowsManualIris,
                        leftIcon: { Image(systemName: "camera.aperture").font(.system(size: 11)) },
                        rightIcon: { Image(systemName: "camera.aperture").font(.system(size: 13, weight: .bold)) }
                    ) { _ = camera.setIrisAbsolute($0) }
                }

                if camera.rollAbsolute.isSupported {
                    PanelSliderRow(
                        label: "Roll",
                        labelWidth: 68,
                        state: camera.rollAbsolute,
                        formattedValue: "\(camera.rollAbsolute.current)°",
                        leftIcon: { Image(systemName: "rotate.left").font(.system(size: 12)) },
                        rightIcon: { Image(systemName: "rotate.right").font(.system(size: 12)) }
                    ) { _ = camera.setRollAbsolute($0) }
                }

                if camera.privacy.isSupported {
                    HStack(spacing: 6) {
                        Toggle(
                            "Hardware Privacy Shutter",
                            isOn: Binding(
                                get: { camera.privacy.current },
                                set: { _ = camera.setPrivacy($0) }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))

                        Spacer()

                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.secondary)

                        RollbackIconButton(
                            isEnabled: camera.privacy.canSet,
                            isModified: camera.privacy.current != camera.privacy.defaultValue,
                            helpText: "Rollback Privacy Shutter to default"
                        ) {
                            _ = camera.setPrivacy(camera.privacy.defaultValue)
                        }

                        Text(camera.privacy.current ? "Closed" : "Open")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(
                                camera.privacy.current == camera.privacy.defaultValue ? Color.secondary : Color.accentColor
                            )
                    }
                    .padding(.leading, 74)
                }

                if camera.scanningMode.isSupported {
                    HStack(spacing: 6) {
                        Toggle(
                            "Progressive Scan",
                            isOn: Binding(
                                get: { camera.scanningMode.current },
                                set: { _ = camera.setScanningMode($0) }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))

                        Spacer()

                        Image(systemName: "lines.measurement.horizontal")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.secondary)

                        RollbackIconButton(
                            isEnabled: camera.scanningMode.canSet,
                            isModified: camera.scanningMode.current != camera.scanningMode.defaultValue,
                            helpText: "Rollback Scanning Mode to default"
                        ) {
                            _ = camera.setScanningMode(camera.scanningMode.defaultValue)
                        }

                        Text(camera.scanningMode.current ? "Prog" : "Interl")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(
                                camera.scanningMode.current == camera.scanningMode.defaultValue ? Color.secondary : Color.accentColor
                            )
                    }
                    .padding(.leading, 74)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - VideoStreaming Resolution & Compatible FPS Section

    @ViewBuilder
    private var videoStreamSection: some View {
        let codecs = camera.availableStreamCodecs
        let resolutions = camera.currentStreamResolutions
        let activeMode = camera.currentStreamMode
        let selected = camera.selectedStream
        let defStream = camera.defaultStream
        let allTiers = camera.availableFPSTiers

        PanelGroupBox(
            "Video Resolution & Frame Rate",
            headerTrailing: {
                if let sel = selected {
                    HStack(spacing: 5) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)

                        RollbackIconButton(
                            isEnabled: defStream != nil,
                            isModified: camera.isStreamModifiedFromDefault,
                            helpText: defStream != nil
                                ? "Rollback format, resolution & FPS to camera default (\(defStream!.detailedSummary))"
                                : "No default stream mode"
                        ) {
                            _ = camera.resetStreamToDefault()
                        }

                        Text(sel.compactSummary)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(camera.isStreamModifiedFromDefault ? Color.accentColor : Color.secondary)
                    }
                }
            }
        ) {
            if camera.streamModes.isEmpty {
                Text("No UVC VideoStreaming descriptors exposed by this device.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                // 1) Payload Format Selector (e.g. MJPEG vs Uncompressed YUY2)
                if codecs.count > 1 {
                    let curCodec = selected?.codec ?? codecs.first!
                    let defCodec = defStream?.codec ?? codecs.first!
                    HStack(spacing: 6) {
                        Text("Format")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .trailing)

                        HardwareSegmentedBar(
                            options: codecs.map { c in
                                SegmentedOptionItem(id: c, title: c.title, isEnabled: true)
                            },
                            selectedID: curCodec,
                            isControlSupported: true,
                            compact: true
                        ) { chosenCodec in
                            _ = camera.selectStreamCodec(chosenCodec)
                        }

                        Image(systemName: "film.stack")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 16, height: 16)

                        RollbackIconButton(
                            isEnabled: true,
                            isModified: curCodec != defCodec,
                            helpText: "Rollback stream format to default (\(defCodec.title))"
                        ) {
                            _ = camera.selectStreamCodec(defCodec)
                        }

                        Text(curCodec.shortTitle)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(curCodec == defCodec ? Color.secondary : Color.accentColor)
                            .frame(minWidth: 58, alignment: .trailing)
                    }
                }

                // 2) Hardware Resolution Picker (Sorted Highest e.g. 2K/4K -> Lowest)
                if !resolutions.isEmpty {
                    let currentKey = selected?.resolutionKey ?? resolutions.first!.resolutionKey
                    let defaultKey = defStream?.resolutionKey ?? resolutions.first!.resolutionKey
                    let isResModified = currentKey != defaultKey

                    HStack(spacing: 6) {
                        Text("Resolution")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .trailing)

                        Picker(
                            "",
                            selection: Binding(
                                get: { currentKey },
                                set: { newKey in
                                    if let matched = resolutions.first(where: { $0.resolutionKey == newKey }) {
                                        _ = camera.selectStreamResolution(width: matched.width, height: matched.height)
                                    }
                                }
                            )
                        ) {
                            ForEach(resolutions) { resMode in
                                Text(resMode.pickerTitle)
                                    .tag(resMode.resolutionKey)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)

                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 16, height: 16)

                        RollbackIconButton(
                            isEnabled: defStream != nil,
                            isModified: isResModified,
                            helpText: defStream != nil
                                ? "Rollback resolution to default (\(defStream!.width)×\(defStream!.height))"
                                : "Reset resolution"
                        ) {
                            if let def = defStream {
                                _ = camera.selectStreamResolution(width: def.width, height: def.height)
                            }
                        }

                        Text(selected != nil ? "\(selected!.width)×\(selected!.height)" : currentKey)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(isResModified ? Color.accentColor : Color.secondary)
                            .frame(minWidth: 58, alignment: .trailing)
                    }
                }

                // 3) Compatible FPS Selector (Validates per-resolution FPS compatibility dynamically!)
                if !allTiers.isEmpty, let mode = activeMode {
                    let curFPS = selected?.fps ?? mode.defaultFPS
                    let defFPS = mode.defaultFPS
                    let isFPSModified = curFPS != defFPS
                    let compactFPSLabels = allTiers.count > 5

                    HStack(spacing: 6) {
                        Text("FPS")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .trailing)

                        HardwareSegmentedBar(
                            options: allTiers.map { tier in
                                SegmentedOptionItem(
                                    id: tier,
                                    title: compactFPSLabels ? "\(tier)" : "\(tier) fps",
                                    isEnabled: mode.supports(fps: tier)
                                )
                            },
                            selectedID: curFPS,
                            isControlSupported: true,
                            compact: true
                        ) { chosenFPS in
                            _ = camera.selectStreamFPS(chosenFPS)
                        }

                        Image(systemName: "speedometer")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 16, height: 16)

                        RollbackIconButton(
                            isEnabled: true,
                            isModified: isFPSModified,
                            helpText: "Rollback FPS to resolution default (\(defFPS) fps)"
                        ) {
                            _ = camera.selectStreamFPS(defFPS)
                        }

                        Text("\(curFPS) fps")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(isFPSModified ? Color.accentColor : Color.secondary)
                            .frame(minWidth: 58, alignment: .trailing)
                    }

                    // 4) Hardware Compatibility & Live Stream Readout Footer
                    let compatList = mode.supportedFPS.map { "\($0.fps)" }.joined(separator: ", ")
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.accentColor)
                            Text("Compatible at \(mode.displayTitle) [\(mode.codec.shortTitle)]: \(compatList) fps (max \(mode.maxFPS) fps)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if !camera.streamStatusNote.isEmpty {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(camera.isHardwareStreamingActive ? Color.green : Color.blue)
                                    .frame(width: 5.5, height: 5.5)
                                Text(camera.streamStatusNote)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}
