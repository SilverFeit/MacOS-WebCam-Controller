import SwiftUI
import UVCCore

public struct BasicTabView: View {
    @ObservedObject var camera: UVCCameraDevice
    let compact: Bool
    let hideUnsupported: Bool

    public init(camera: UVCCameraDevice, compact: Bool = false, hideUnsupported: Bool = false) {
        self.camera = camera
        self.compact = compact
        self.hideUnsupported = hideUnsupported
    }

    private var labelWidth: CGFloat { compact ? 84 : 96 }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 11) {
            // 1. Exposure Section (Auto-Exposure Mode + Exposure Time + Gain)
            if !hideUnsupported || camera.autoExposureMode.isSupported || camera.exposureTime.isSupported || camera.gain.isSupported {
                PanelGroupBox("Exposure") {
                    if !hideUnsupported || camera.autoExposureMode.isSupported {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text("Auto-Exposure Mode")
                                    .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Image(systemName: "camera.metering.multispot")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.secondary)
                                    .opacity(camera.autoExposureMode.isSupported ? 0.9 : 0.35)

                                RollbackIconButton(
                                    isEnabled: camera.autoExposureMode.isSupported && camera.autoExposureMode.canSet,
                                    isModified: camera.autoExposureMode.isSupported && camera.autoExposureMode.current != camera.autoExposureMode.defaultMode,
                                    helpText: "Rollback Auto-Exposure Mode to default (\(camera.autoExposureMode.defaultMode.title))"
                                ) {
                                    _ = camera.setAutoExposureMode(camera.autoExposureMode.defaultMode)
                                }

                                Text(camera.autoExposureMode.isSupported ? camera.autoExposureMode.current.shortTitle : "N/A")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(
                                        !camera.autoExposureMode.isSupported ? Color.secondary.opacity(0.4) :
                                        (camera.autoExposureMode.current == camera.autoExposureMode.defaultMode ? Color.secondary : Color.accentColor)
                                    )
                            }

                            HardwareSegmentedBar(
                                options: AutoExposureMode.allCases.map { mode in
                                    SegmentedOptionItem(
                                        id: mode,
                                        title: compact ? mode.shortTitle : mode.title,
                                        isEnabled: camera.autoExposureMode.isModeSupported(mode)
                                    )
                                },
                                selectedID: camera.autoExposureMode.current,
                                isControlSupported: camera.autoExposureMode.isSupported,
                                compact: compact
                            ) { selectedMode in
                                _ = camera.setAutoExposureMode(selectedMode)
                            }
                        }
                    }

                    if !hideUnsupported || camera.exposureTime.isSupported {
                        PanelSliderRow(
                            label: "Exposure Time",
                            labelWidth: labelWidth,
                            state: camera.exposureTime,
                            isLockedByAuto: !camera.autoExposureMode.allowsManualExposureTime,
                            leftIcon: {
                                Image(systemName: "stopwatch")
                                    .font(.system(size: 12))
                            },
                            rightIcon: {
                                Image(systemName: "stopwatch.fill")
                                    .font(.system(size: 12))
                            }
                        ) { newValue in
                            _ = camera.setExposureTime(newValue)
                        }
                    }

                    if !hideUnsupported || camera.gain.isSupported {
                        PanelSliderRow(
                            label: "Gain",
                            labelWidth: labelWidth,
                            state: camera.gain,
                            leftIcon: {
                                Image(systemName: "cellularbars", variableValue: 0.25)
                                    .font(.system(size: 12))
                            },
                            rightIcon: {
                                Image(systemName: "cellularbars", variableValue: 1.0)
                                    .font(.system(size: 12))
                            }
                        ) { newValue in
                            _ = camera.setGain(newValue)
                        }
                    }
                }
            }

            // 2. Image Controls (Brightness, Contrast, Hue, Saturation, Sharpness, Gamma)
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                if !hideUnsupported || camera.brightness.isSupported {
                    PanelSliderRow(
                        label: "Brightness",
                        labelWidth: labelWidth,
                        state: camera.brightness,
                        leftIcon: {
                            Image(systemName: "sun.min")
                                .font(.system(size: 12))
                        },
                        rightIcon: {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 13))
                        }
                    ) { _ = camera.setBrightness($0) }
                }

                if !hideUnsupported || camera.contrast.isSupported {
                    PanelSliderRow(
                        label: "Contrast",
                        labelWidth: labelWidth,
                        state: camera.contrast,
                        isLockedByAuto: camera.contrastAuto.isSupported && camera.contrastAuto.current,
                        leftIcon: { DiamondBadgeIcon(.lowContrast) },
                        rightIcon: { DiamondBadgeIcon(.highContrast) }
                    ) { _ = camera.setContrast($0) }
                }

                if !hideUnsupported || camera.hue.isSupported {
                    PanelSliderRow(
                        label: "Hue",
                        labelWidth: labelWidth,
                        state: camera.hue,
                        isLockedByAuto: camera.hueAuto.isSupported && camera.hueAuto.current,
                        leftIcon: { DiamondBadgeIcon(.hueLeft) },
                        rightIcon: { DiamondBadgeIcon(.hueRight) }
                    ) { _ = camera.setHue($0) }
                }

                if !hideUnsupported || camera.saturation.isSupported {
                    PanelSliderRow(
                        label: "Saturation",
                        labelWidth: labelWidth,
                        state: camera.saturation,
                        leftIcon: { DiamondBadgeIcon(.saturationLow) },
                        rightIcon: { DiamondBadgeIcon(.saturationHigh) }
                    ) { _ = camera.setSaturation($0) }
                }

                if !hideUnsupported || camera.sharpness.isSupported {
                    PanelSliderRow(
                        label: "Sharpness",
                        labelWidth: labelWidth,
                        state: camera.sharpness,
                        leftIcon: { DiamondBadgeIcon(.sharpnessSoft) },
                        rightIcon: { DiamondBadgeIcon(.sharpnessCrisp) }
                    ) { _ = camera.setSharpness($0) }
                }

                if !hideUnsupported || camera.gamma.isSupported {
                    PanelSliderRow(
                        label: "Gamma",
                        labelWidth: labelWidth,
                        state: camera.gamma,
                        leftIcon: { DiamondBadgeIcon(.gammaLow) },
                        rightIcon: { DiamondBadgeIcon(.gammaHigh) }
                    ) { _ = camera.setGamma($0) }
                }
            }
            .padding(.horizontal, 4)

            // 3. White Balance Temperature Section
            if !hideUnsupported || camera.whiteBalanceAuto.isSupported || camera.whiteBalanceTemperature.isSupported {
                PanelGroupBox(
                    "White Balance Temperature",
                    headerTrailing: {
                        if camera.whiteBalanceAuto.isSupported {
                            HStack(spacing: 5) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                                    .opacity(0.9)

                                RollbackIconButton(
                                    isEnabled: camera.whiteBalanceAuto.canSet,
                                    isModified: camera.whiteBalanceAuto.current != camera.whiteBalanceAuto.defaultValue,
                                    helpText: "Rollback White Balance Auto mode to default (\(camera.whiteBalanceAuto.defaultValue ? "Auto" : "Manual"))"
                                ) {
                                    _ = camera.setWhiteBalanceAuto(camera.whiteBalanceAuto.defaultValue)
                                }

                                Text(camera.whiteBalanceAuto.current ? "Auto" : "Manual")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(
                                        camera.whiteBalanceAuto.current == camera.whiteBalanceAuto.defaultValue
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
                                get: { camera.whiteBalanceAuto.current },
                                set: { _ = camera.setWhiteBalanceAuto($0) }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .disabled(!camera.whiteBalanceAuto.isSupported)

                        Text("#")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        PanelSliderRow(
                            label: "",
                            labelWidth: 0,
                            state: camera.whiteBalanceTemperature,
                            isLockedByAuto: camera.whiteBalanceAuto.isSupported && camera.whiteBalanceAuto.current,
                            formattedValue: camera.whiteBalanceTemperature.isSupported ? "\(camera.whiteBalanceTemperature.current)K" : nil,
                            leftIcon: { DiamondBadgeIcon(.kelvinCool) },
                            rightIcon: { DiamondBadgeIcon(.kelvinWarm) }
                        ) { newKelvin in
                            _ = camera.setWhiteBalanceTemperature(newKelvin)
                        }
                    }
                }
            }
        }
    }
}
