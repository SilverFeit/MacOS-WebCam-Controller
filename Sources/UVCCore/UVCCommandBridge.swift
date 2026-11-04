import Foundation

public enum UVCCommandError: Error, Equatable, CustomStringConvertible {
    case unknownControl(String)
    case unsupportedControl(String)
    case readOnlyControl(String)
    case invalidValue(control: String, value: String, hint: String)
    case hardwareWriteFailed(control: String, reason: String)

    public var description: String {
        switch self {
        case let .unknownControl(name):
            return "unknown control '\(name)' (run `webcamctl get` to see supported controls)"
        case let .unsupportedControl(name):
            return "control '\(name)' is not supported by this camera"
        case let .readOnlyControl(name):
            return "control '\(name)' is read-only on this camera"
        case let .invalidValue(control, value, hint):
            return "invalid value '\(value)' for \(control) (\(hint))"
        case let .hardwareWriteFailed(control, reason):
            return "failed to write \(control): \(reason)"
        }
    }
}

public struct UVCControlReadout: Equatable, Sendable {
    public let id: String
    public let name: String
    public let isSupported: Bool
    public let isWritable: Bool
    public let isLockedByAuto: Bool
    public let currentValue: String
    public let formattedDisplay: String
    public let minimum: Int?
    public let maximum: Int?
    public let step: Int?
    public let defaultValue: String?
    public let choices: [String]

    public func toJSONObject() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "supported": isSupported,
            "writable": isWritable,
            "locked_by_auto": isLockedByAuto,
            "value": currentValue,
            "formatted": formattedDisplay
        ]
        if let minimum { dict["min"] = minimum }
        if let maximum { dict["max"] = maximum }
        if let step { dict["step"] = step }
        if let defaultValue { dict["default"] = defaultValue }
        if !choices.isEmpty { dict["choices"] = choices }
        return dict
    }

    public func formattedCLILine() -> String {
        let idCol = id.padding(toLength: 24, withPad: " ", startingAt: 0)
        let valText = formattedDisplay == currentValue
            ? currentValue
            : "\(currentValue) (\(formattedDisplay))"
        let valCol = valText.padding(toLength: 22, withPad: " ", startingAt: 0)

        var details: [String] = []
        if let lo = minimum, let hi = maximum {
            details.append("range \(lo)...\(hi)")
        }
        if let st = step, st > 1 {
            details.append("step \(st)")
        }
        if let def = defaultValue {
            details.append("default \(def)")
        }
        if !choices.isEmpty {
            details.append("choices: " + choices.joined(separator: ", "))
        }
        if isLockedByAuto {
            details.append("locked by auto")
        } else if !isWritable {
            details.append("read-only")
        }
        return "\(idCol) \(valCol) \(details.joined(separator: "; "))"
    }
}

extension UVCCameraDevice {
    public static let canonicalControlIDs: [String] = [
        "exposure_mode",
        "exposure_time",
        "gain",
        "exposure_priority",
        "brightness",
        "contrast_auto",
        "contrast",
        "hue_auto",
        "hue",
        "saturation",
        "sharpness",
        "gamma",
        "white_balance_auto",
        "white_balance",
        "power_line_frequency",
        "backlight_compensation",
        "focus_auto",
        "focus",
        "zoom",
        "digital_zoom",
        "pan",
        "tilt",
        "iris",
        "roll",
        "scanning_mode",
        "privacy",
        "stream"
    ]

    public static func normalizeControlID(_ raw: String) -> String? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "exposure_mode", "ae_mode", "auto_exposure_mode":
            return "exposure_mode"
        case "exposure_time", "shutter", "shutter_speed", "exposure":
            return "exposure_time"
        case "gain", "iso":
            return "gain"
        case "exposure_priority", "ae_priority", "low_light", "low_light_compensation":
            return "exposure_priority"
        case "brightness":
            return "brightness"
        case "contrast_auto", "auto_contrast":
            return "contrast_auto"
        case "contrast":
            return "contrast"
        case "hue_auto", "auto_hue":
            return "hue_auto"
        case "hue":
            return "hue"
        case "saturation":
            return "saturation"
        case "sharpness":
            return "sharpness"
        case "gamma":
            return "gamma"
        case "white_balance_auto", "wb_auto", "auto_white_balance", "awb":
            return "white_balance_auto"
        case "white_balance", "white_balance_temperature", "kelvin", "wb", "temperature":
            return "white_balance"
        case "power_line_frequency", "anti_flicker", "flicker", "powerline":
            return "power_line_frequency"
        case "backlight_compensation", "backlight", "hdr":
            return "backlight_compensation"
        case "focus_auto", "autofocus", "af":
            return "focus_auto"
        case "focus", "focus_absolute":
            return "focus"
        case "zoom", "zoom_absolute":
            return "zoom"
        case "digital_zoom", "digital_multiplier":
            return "digital_zoom"
        case "pan", "pan_absolute":
            return "pan"
        case "tilt", "tilt_absolute":
            return "tilt"
        case "iris", "iris_absolute", "aperture":
            return "iris"
        case "roll", "roll_absolute":
            return "roll"
        case "scanning_mode", "progressive":
            return "scanning_mode"
        case "privacy", "shutter_privacy":
            return "privacy"
        case "stream", "video", "resolution", "fps", "format", "codec":
            return normalized == "video" ? "stream" : normalized
        default:
            return nil
        }
    }

    public func readAllSupportedControls() -> [UVCControlReadout] {
        Self.canonicalControlIDs.compactMap { id in
            guard let r = try? readControl(id), r.isSupported else { return nil }
            return r
        }
    }

    public func readControl(_ rawID: String) throws -> UVCControlReadout {
        guard let id = Self.normalizeControlID(rawID) else {
            throw UVCCommandError.unknownControl(rawID)
        }
        let targetID = (id == "resolution" || id == "fps" || id == "format" || id == "codec") ? "stream" : id

        switch targetID {
        case "exposure_mode":
            let s = autoExposureMode
            let modes = AutoExposureMode.supportedModes(fromBitmask: s.supportedBitmask)
                .map { "\($0.rawValue)=\($0.shortTitle.lowercased())" }
            return UVCControlReadout(
                id: "exposure_mode",
                name: "Auto-Exposure Mode",
                isSupported: s.isSupported,
                isWritable: s.canSet,
                isLockedByAuto: false,
                currentValue: "\(s.current.rawValue)",
                formattedDisplay: s.current.title,
                minimum: nil,
                maximum: nil,
                step: nil,
                defaultValue: "\(s.defaultMode.rawValue) (\(s.defaultMode.shortTitle))",
                choices: modes
            )

        case "exposure_time":
            return rangeReadout(
                "exposure_time",
                "Exposure Time (Shutter)",
                exposureTime,
                lockedByAuto: !autoExposureMode.allowsManualExposureTime,
                formatted: exposureTime.formattedShutterShort
            )

        case "gain":
            return rangeReadout("gain", "Gain (ISO)", gain)

        case "exposure_priority":
            return boolReadout("exposure_priority", "Low-Light Compensation", autoExposurePriority)

        case "brightness":
            return rangeReadout("brightness", "Brightness", brightness)

        case "contrast_auto":
            return boolReadout("contrast_auto", "Auto Contrast", contrastAuto)

        case "contrast":
            return rangeReadout(
                "contrast",
                "Contrast",
                contrast,
                lockedByAuto: contrastAuto.isSupported && contrastAuto.current
            )

        case "hue_auto":
            return boolReadout("hue_auto", "Auto Hue", hueAuto)

        case "hue":
            return rangeReadout(
                "hue",
                "Hue",
                hue,
                lockedByAuto: hueAuto.isSupported && hueAuto.current
            )

        case "saturation":
            return rangeReadout("saturation", "Saturation", saturation)

        case "sharpness":
            return rangeReadout("sharpness", "Sharpness", sharpness)

        case "gamma":
            return rangeReadout("gamma", "Gamma", gamma, formatted: gamma.formattedGamma)

        case "white_balance_auto":
            return boolReadout("white_balance_auto", "Auto White Balance", whiteBalanceAuto)

        case "white_balance":
            return rangeReadout(
                "white_balance",
                "White Balance (Kelvin)",
                whiteBalanceTemperature,
                lockedByAuto: whiteBalanceAuto.isSupported && whiteBalanceAuto.current,
                formatted: "\(whiteBalanceTemperature.current) K"
            )

        case "power_line_frequency":
            let s = powerLineFrequency
            let validChoices = PowerLineFrequency.allCases
                .filter { $0.rawValue >= s.minimum && $0.rawValue <= s.maximum }
                .map { "\($0.rawValue)=\($0.title)" }
            let curLabel = PowerLineFrequency(rawValue: s.current)?.title ?? "\(s.current)"
            let defLabel = PowerLineFrequency(rawValue: s.defaultValue)?.title ?? "\(s.defaultValue)"
            return UVCControlReadout(
                id: "power_line_frequency",
                name: "Power Line Frequency",
                isSupported: s.isSupported,
                isWritable: s.canSet,
                isLockedByAuto: false,
                currentValue: "\(s.current)",
                formattedDisplay: curLabel,
                minimum: s.minimum,
                maximum: s.maximum,
                step: 1,
                defaultValue: "\(s.defaultValue) (\(defLabel))",
                choices: validChoices
            )

        case "backlight_compensation":
            return rangeReadout("backlight_compensation", "Backlight Compensation", backlightCompensation)

        case "focus_auto":
            return boolReadout("focus_auto", "Auto Focus", focusAuto)

        case "focus":
            return rangeReadout(
                "focus",
                "Focus",
                focusAbsolute,
                lockedByAuto: focusAuto.isSupported && focusAuto.current
            )

        case "zoom":
            return rangeReadout("zoom", "Optical Zoom", zoomAbsolute, formatted: zoomAbsolute.formattedZoomShort)

        case "digital_zoom":
            return rangeReadout("digital_zoom", "Digital Zoom", digitalMultiplier)

        case "pan":
            return rangeReadout("pan", "Pan", panAbsolute, formatted: panAbsolute.formattedArcsecondsDegrees)

        case "tilt":
            return rangeReadout("tilt", "Tilt", tiltAbsolute, formatted: tiltAbsolute.formattedArcsecondsDegrees)

        case "iris":
            return rangeReadout(
                "iris",
                "Aperture / Iris",
                irisAbsolute,
                lockedByAuto: !autoExposureMode.allowsManualIris
            )

        case "roll":
            return rangeReadout("roll", "Roll", rollAbsolute, formatted: "\(rollAbsolute.current)°")

        case "scanning_mode":
            return boolReadout("scanning_mode", "Progressive Scan", scanningMode)

        case "privacy":
            return boolReadout("privacy", "Privacy Shutter", privacy)

        case "stream":
            let supported = !streamModes.isEmpty
            let cur = selectedStream?.detailedSummary ?? "N/A"
            let def = defaultStream?.detailedSummary
            let codecs = availableStreamCodecs.map { $0.shortTitle.lowercased() }
            return UVCControlReadout(
                id: "stream",
                name: "USB Video Stream",
                isSupported: supported,
                isWritable: supported,
                isLockedByAuto: false,
                currentValue: selectedStream.map { "\($0.width)x\($0.height)@\($0.fps)" } ?? "N/A",
                formattedDisplay: cur,
                minimum: nil,
                maximum: nil,
                step: nil,
                defaultValue: def,
                choices: codecs
            )

        default:
            throw UVCCommandError.unknownControl(rawID)
        }
    }

    @discardableResult
    public func writeControl(_ rawID: String, rawValue: String) throws -> UVCControlReadout {
        guard let id = Self.normalizeControlID(rawID) else {
            throw UVCCommandError.unknownControl(rawID)
        }
        let val = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch id {
        case "exposure_mode":
            guard autoExposureMode.isSupported else { throw UVCCommandError.unsupportedControl(id) }
            guard let mode = parseExposureMode(val) else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "expected manual, auto, shutter, aperture, or 1/2/4/8")
            }
            guard autoExposureMode.isModeSupported(mode) else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "mode '\(mode.title)' is not supported by this camera")
            }
            guard setAutoExposureMode(mode) else {
                throw UVCCommandError.hardwareWriteFailed(control: id, reason: lastHardwareErrorDescription ?? "USB write failed")
            }

        case "exposure_time":
            guard exposureTime.isSupported else { throw UVCCommandError.unsupportedControl(id) }
            if !autoExposureMode.allowsManualExposureTime && autoExposureMode.isSupported {
                if autoExposureMode.isModeSupported(.manual) {
                    _ = setAutoExposureMode(.manual)
                    usleep(4_000)
                } else if autoExposureMode.isModeSupported(.shutterPriority) {
                    _ = setAutoExposureMode(.shutterPriority)
                    usleep(4_000)
                }
            }
            let target: Int
            if val.hasPrefix("+") || val.hasPrefix("-"), let delta = Int(val) {
                target = exposureTime.current + delta
            } else if let parsedShutter = UVCValueFormatter.parseShutterUnits(val) {
                target = parsedShutter
            } else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "expected 100µs integer or shutter fraction like 1/60")
            }
            guard setExposureTime(target) else {
                throw UVCCommandError.hardwareWriteFailed(control: id, reason: lastHardwareErrorDescription ?? "USB write failed")
            }

        case "gain":
            try applyNumericRange(id, val, state: gain, setter: setGain)

        case "exposure_priority":
            try applyBool(id, val, state: autoExposurePriority, setter: setAutoExposurePriority)

        case "brightness":
            try applyNumericRange(id, val, state: brightness, setter: setBrightness)

        case "contrast_auto":
            try applyBool(id, val, state: contrastAuto, setter: setContrastAuto)

        case "contrast":
            if contrastAuto.isSupported && contrastAuto.current {
                _ = setContrastAuto(false)
                usleep(4_000)
            }
            try applyNumericRange(id, val, state: contrast, setter: setContrast)

        case "hue_auto":
            try applyBool(id, val, state: hueAuto, setter: setHueAuto)

        case "hue":
            if hueAuto.isSupported && hueAuto.current {
                _ = setHueAuto(false)
                usleep(4_000)
            }
            try applyNumericRange(id, val, state: hue, setter: setHue)

        case "saturation":
            try applyNumericRange(id, val, state: saturation, setter: setSaturation)

        case "sharpness":
            try applyNumericRange(id, val, state: sharpness, setter: setSharpness)

        case "gamma":
            try applyNumericRange(id, val, state: gamma, setter: setGamma)

        case "white_balance_auto":
            try applyBool(id, val, state: whiteBalanceAuto, setter: setWhiteBalanceAuto)

        case "white_balance":
            guard whiteBalanceTemperature.isSupported else { throw UVCCommandError.unsupportedControl(id) }
            if val.lowercased() == "auto" {
                guard whiteBalanceAuto.isSupported, setWhiteBalanceAuto(true) else {
                    throw UVCCommandError.hardwareWriteFailed(control: "white_balance_auto", reason: "cannot enable auto white balance")
                }
                return try readControl("white_balance_auto")
            }
            if whiteBalanceAuto.isSupported && whiteBalanceAuto.current {
                _ = setWhiteBalanceAuto(false)
                usleep(4_000)
            }
            let cleaned = val.lowercased().hasSuffix("k") ? String(val.dropLast()) : val
            try applyNumericRange(id, cleaned, state: whiteBalanceTemperature, setter: setWhiteBalanceTemperature)

        case "power_line_frequency":
            guard powerLineFrequency.isSupported else { throw UVCCommandError.unsupportedControl(id) }
            guard let freqVal = parsePowerLine(val) else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "expected off/0, 50hz/1, 60hz/2, or auto/3")
            }
            guard freqVal >= powerLineFrequency.minimum && freqVal <= powerLineFrequency.maximum else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "supported range is \(powerLineFrequency.minimum)...\(powerLineFrequency.maximum)")
            }
            guard setPowerLineFrequency(freqVal) else {
                throw UVCCommandError.hardwareWriteFailed(control: id, reason: lastHardwareErrorDescription ?? "USB write failed")
            }

        case "backlight_compensation":
            if let b = parseBoolToken(val) {
                guard backlightCompensation.isSupported else { throw UVCCommandError.unsupportedControl(id) }
                guard setBacklightEnabled(b) else {
                    throw UVCCommandError.hardwareWriteFailed(control: id, reason: lastHardwareErrorDescription ?? "USB write failed")
                }
            } else {
                try applyNumericRange(id, val, state: backlightCompensation, setter: setBacklightCompensation)
            }

        case "focus_auto":
            try applyBool(id, val, state: focusAuto, setter: setFocusAuto)

        case "focus":
            guard focusAbsolute.isSupported else { throw UVCCommandError.unsupportedControl(id) }
            if val.lowercased() == "auto" {
                guard focusAuto.isSupported, setFocusAuto(true) else {
                    throw UVCCommandError.hardwareWriteFailed(control: "focus_auto", reason: "cannot enable autofocus")
                }
                return try readControl("focus_auto")
            }
            if focusAuto.isSupported && focusAuto.current {
                _ = setFocusAuto(false)
                usleep(4_000)
            }
            try applyNumericRange(id, val, state: focusAbsolute, setter: setFocusAbsolute)

        case "zoom":
            if zoomAbsolute.isSupported {
                try applyNumericRange(id, val, state: zoomAbsolute, setter: setZoomAbsolute)
            } else if digitalMultiplier.isSupported {
                try applyNumericRange("digital_zoom", val, state: digitalMultiplier, setter: setDigitalMultiplier)
            } else {
                throw UVCCommandError.unsupportedControl(id)
            }

        case "digital_zoom":
            try applyNumericRange(id, val, state: digitalMultiplier, setter: setDigitalMultiplier)

        case "pan":
            try applyNumericRange(id, val, state: panAbsolute, setter: setPanAbsolute)

        case "tilt":
            try applyNumericRange(id, val, state: tiltAbsolute, setter: setTiltAbsolute)

        case "iris":
            if !autoExposureMode.allowsManualIris && autoExposureMode.isSupported && autoExposureMode.isModeSupported(.manual) {
                _ = setAutoExposureMode(.manual)
                usleep(4_000)
            }
            try applyNumericRange(id, val, state: irisAbsolute, setter: setIrisAbsolute)

        case "roll":
            try applyNumericRange(id, val, state: rollAbsolute, setter: setRollAbsolute)

        case "scanning_mode":
            try applyBool(id, val, state: scanningMode, setter: setScanningMode)

        case "privacy":
            try applyBool(id, val, state: privacy, setter: setPrivacy)

        case "resolution":
            guard !streamModes.isEmpty else { throw UVCCommandError.unsupportedControl("stream") }
            guard let (w, h) = Self.parseResolutionToken(val) else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "expected WxH like 2560x1440, 1920x1080, 1280x720, or 2k/1080p/720p")
            }
            guard selectStreamResolution(width: w, height: h) else {
                throw UVCCommandError.hardwareWriteFailed(control: id, reason: "resolution \(w)x\(h) not supported or USB probe failed")
            }
            return try readControl("stream")

        case "fps":
            guard !streamModes.isEmpty else { throw UVCCommandError.unsupportedControl("stream") }
            let cleaned = val.lowercased().replacingOccurrences(of: "fps", with: "")
            guard let fps = Int(cleaned), fps > 0 else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "expected integer FPS such as 30 or 60")
            }
            guard selectStreamFPS(fps) else {
                throw UVCCommandError.hardwareWriteFailed(control: id, reason: "FPS \(fps) incompatible with active resolution")
            }
            return try readControl("stream")

        case "format", "codec":
            guard !streamModes.isEmpty else { throw UVCCommandError.unsupportedControl("stream") }
            guard let codec = Self.parseCodecToken(val) else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "expected mjpeg, yuy2/uncompressed, or h264")
            }
            guard selectStreamCodec(codec) else {
                throw UVCCommandError.hardwareWriteFailed(control: id, reason: "codec \(codec.shortTitle) not supported")
            }
            return try readControl("stream")

        case "stream":
            // Accepts e.g. 2560x1440@30 or 1920x1080
            let parts = val.split(separator: "@", maxSplits: 1).map(String.init)
            guard let (w, h) = Self.parseResolutionToken(parts[0]) else {
                throw UVCCommandError.invalidValue(control: id, value: val, hint: "expected WxH[@FPS] such as 2560x1440@30")
            }
            let desiredFPS = (parts.count == 2 ? Int(parts[1].lowercased().replacingOccurrences(of: "fps", with: "")) : nil)
                ?? selectedStream?.fps ?? 30
            let desiredCodec = selectedStream?.codec ?? availableStreamCodecs.first ?? .mjpeg
            guard let validated = UVCStreamValidator.validateSelection(
                modes: streamModes,
                desiredCodec: desiredCodec,
                desiredWidth: w,
                desiredHeight: h,
                desiredFPS: desiredFPS
            ), applyStreamSelection(validated) else {
                throw UVCCommandError.hardwareWriteFailed(control: id, reason: "stream \(val) could not be negotiated")
            }

        default:
            throw UVCCommandError.unknownControl(rawID)
        }

        return try readControl(id)
    }

    @discardableResult
    public func resetControl(_ rawID: String) throws -> UVCControlReadout {
        guard let id = Self.normalizeControlID(rawID) else {
            throw UVCCommandError.unknownControl(rawID)
        }
        let targetID = (id == "resolution" || id == "fps" || id == "format" || id == "codec") ? "stream" : id

        switch targetID {
        case "exposure_mode":
            guard autoExposureMode.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setAutoExposureMode(autoExposureMode.defaultMode)
        case "exposure_time":
            guard exposureTime.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            if !autoExposureMode.allowsManualExposureTime && autoExposureMode.isModeSupported(.manual) {
                _ = setAutoExposureMode(.manual)
                usleep(4_000)
            }
            _ = setExposureTime(exposureTime.defaultValue)
        case "gain":
            guard gain.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setGain(gain.defaultValue)
        case "exposure_priority":
            guard autoExposurePriority.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setAutoExposurePriority(autoExposurePriority.defaultValue)
        case "brightness":
            guard brightness.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setBrightness(brightness.defaultValue)
        case "contrast_auto":
            guard contrastAuto.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setContrastAuto(contrastAuto.defaultValue)
        case "contrast":
            guard contrast.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setContrast(contrast.defaultValue)
        case "hue_auto":
            guard hueAuto.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setHueAuto(hueAuto.defaultValue)
        case "hue":
            guard hue.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setHue(hue.defaultValue)
        case "saturation":
            guard saturation.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setSaturation(saturation.defaultValue)
        case "sharpness":
            guard sharpness.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setSharpness(sharpness.defaultValue)
        case "gamma":
            guard gamma.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setGamma(gamma.defaultValue)
        case "white_balance_auto":
            guard whiteBalanceAuto.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setWhiteBalanceAuto(whiteBalanceAuto.defaultValue)
        case "white_balance":
            guard whiteBalanceTemperature.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            if whiteBalanceAuto.isSupported && whiteBalanceAuto.current {
                _ = setWhiteBalanceAuto(false)
                usleep(4_000)
            }
            _ = setWhiteBalanceTemperature(whiteBalanceTemperature.defaultValue)
        case "power_line_frequency":
            guard powerLineFrequency.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setPowerLineFrequency(powerLineFrequency.defaultValue)
        case "backlight_compensation":
            guard backlightCompensation.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setBacklightCompensation(backlightCompensation.defaultValue)
        case "focus_auto":
            guard focusAuto.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setFocusAuto(focusAuto.defaultValue)
        case "focus":
            guard focusAbsolute.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            if focusAuto.isSupported && focusAuto.current {
                _ = setFocusAuto(false)
                usleep(4_000)
            }
            _ = setFocusAbsolute(focusAbsolute.defaultValue)
        case "zoom":
            guard zoomAbsolute.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setZoomAbsolute(zoomAbsolute.defaultValue)
        case "digital_zoom":
            guard digitalMultiplier.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setDigitalMultiplier(digitalMultiplier.defaultValue)
        case "pan":
            guard panAbsolute.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setPanAbsolute(panAbsolute.defaultValue)
        case "tilt":
            guard tiltAbsolute.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setTiltAbsolute(tiltAbsolute.defaultValue)
        case "iris":
            guard irisAbsolute.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setIrisAbsolute(irisAbsolute.defaultValue)
        case "roll":
            guard rollAbsolute.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setRollAbsolute(rollAbsolute.defaultValue)
        case "scanning_mode":
            guard scanningMode.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setScanningMode(scanningMode.defaultValue)
        case "privacy":
            guard privacy.isSupported else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = setPrivacy(privacy.defaultValue)
        case "stream":
            guard !streamModes.isEmpty else { throw UVCCommandError.unsupportedControl(targetID) }
            _ = resetStreamToDefault()
        default:
            throw UVCCommandError.unknownControl(rawID)
        }

        return try readControl(targetID)
    }

    // MARK: - Helpers

    private func rangeReadout(
        _ id: String,
        _ name: String,
        _ s: NumericRangeControlState,
        lockedByAuto: Bool = false,
        formatted: String? = nil
    ) -> UVCControlReadout {
        UVCControlReadout(
            id: id,
            name: name,
            isSupported: s.isSupported,
            isWritable: s.canSet && !lockedByAuto,
            isLockedByAuto: lockedByAuto,
            currentValue: "\(s.current)",
            formattedDisplay: formatted ?? "\(s.current)",
            minimum: s.minimum,
            maximum: s.maximum,
            step: s.step,
            defaultValue: "\(s.defaultValue)",
            choices: []
        )
    }

    private func boolReadout(_ id: String, _ name: String, _ s: BooleanControlState) -> UVCControlReadout {
        UVCControlReadout(
            id: id,
            name: name,
            isSupported: s.isSupported,
            isWritable: s.canSet,
            isLockedByAuto: false,
            currentValue: s.current ? "on" : "off",
            formattedDisplay: s.current ? "on" : "off",
            minimum: nil,
            maximum: nil,
            step: nil,
            defaultValue: s.defaultValue ? "on" : "off",
            choices: ["off", "on"]
        )
    }

    private func applyNumericRange(
        _ id: String,
        _ rawVal: String,
        state: NumericRangeControlState,
        setter: (Int) -> Bool
    ) throws {
        guard state.isSupported else { throw UVCCommandError.unsupportedControl(id) }
        guard state.canSet else { throw UVCCommandError.readOnlyControl(id) }

        let target: Int
        if (rawVal.hasPrefix("+") || rawVal.hasPrefix("-")) && rawVal.count > 1,
           let delta = Int(rawVal) {
            // Distinguish signed absolute value (e.g. brightness=-10) vs explicit step?
            // Note: `+10` is unambiguously relative; for `-10` on unsigned ranges (minimum >= 0), treat as relative delta!
            if rawVal.hasPrefix("+") || state.minimum >= 0 {
                target = state.current + delta
            } else {
                target = delta
            }
        } else if rawVal.hasPrefix("delta:"), let delta = Int(rawVal.dropFirst(6)) {
            target = state.current + delta
        } else if let exact = Int(rawVal) {
            target = exact
        } else {
            throw UVCCommandError.invalidValue(control: id, value: rawVal, hint: "range \(state.minimum)...\(state.maximum)")
        }

        guard setter(target) else {
            throw UVCCommandError.hardwareWriteFailed(control: id, reason: lastHardwareErrorDescription ?? "USB write failed")
        }
    }

    private func applyBool(
        _ id: String,
        _ rawVal: String,
        state: BooleanControlState,
        setter: (Bool) -> Bool
    ) throws {
        guard state.isSupported else { throw UVCCommandError.unsupportedControl(id) }
        guard state.canSet else { throw UVCCommandError.readOnlyControl(id) }
        guard let b = parseBoolToken(rawVal) else {
            throw UVCCommandError.invalidValue(control: id, value: rawVal, hint: "expected on/off, true/false, or 1/0")
        }
        guard setter(b) else {
            throw UVCCommandError.hardwareWriteFailed(control: id, reason: lastHardwareErrorDescription ?? "USB write failed")
        }
    }

    private func parseBoolToken(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "1", "on", "true", "yes", "auto", "enabled":
            return true
        case "0", "off", "false", "no", "manual", "disabled":
            return false
        default:
            return nil
        }
    }

    private func parseExposureMode(_ raw: String) -> AutoExposureMode? {
        switch raw.lowercased() {
        case "1", "manual":
            return .manual
        case "2", "auto":
            return .auto
        case "4", "shutter", "shutter_priority", "shutter-priority":
            return .shutterPriority
        case "8", "aperture", "aperture_priority", "aperture-priority":
            return .aperturePriority
        default:
            return nil
        }
    }

    private func parsePowerLine(_ raw: String) -> Int? {
        switch raw.lowercased() {
        case "0", "off", "disabled", "none":
            return 0
        case "1", "50", "50hz":
            return 1
        case "2", "60", "60hz":
            return 2
        case "3", "auto":
            return 3
        default:
            return nil
        }
    }

    public static func parseResolutionToken(_ raw: String) -> (Int, Int)? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "4k", "2160p", "uhd":
            return (3840, 2160)
        case "2k", "1440p", "qhd":
            return (2560, 1440)
        case "1080p", "fhd":
            return (1920, 1080)
        case "720p", "hd":
            return (1280, 720)
        case "480p", "vga":
            return (640, 480)
        default:
            let parts = lower.split(whereSeparator: { $0 == "x" || $0 == "×" }).map(String.init)
            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 {
                return (w, h)
            }
            return nil
        }
    }

    public static func parseCodecToken(_ raw: String) -> UVCVideoCodec? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mjpeg", "mjpg", "2":
            return .mjpeg
        case "yuy2", "yuyv", "uncompressed", "raw", "1":
            return .uncompressed
        case "h264", "h.264", "frame_based", "framebased", "3":
            return .frameBased
        default:
            return nil
        }
    }
}
