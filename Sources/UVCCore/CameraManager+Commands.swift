import Foundation

extension CameraManager {
    // MARK: - Camera lookup

    /// Finds an attached camera by index, persistent/runtime ID, `VID:PID`, serial number, or name fragment.
    public func findCamera(matching selector: String) -> UVCCameraDevice? {
        let sel = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sel.isEmpty else { return nil }
        if let idx = Int(sel), cameras.indices.contains(idx) {
            return cameras[idx]
        }
        let lower = sel.lowercased()
        return cameras.first { cam in
            let id = cam.identity
            return id.persistentID.lowercased() == lower
                || id.runtimeID.lowercased() == lower
                || id.modelKey.lowercased() == lower
                || id.vidPidHex.lowercased() == lower
                || (!id.serialNumber.isEmpty && id.serialNumber.lowercased() == lower)
                || id.productName.lowercased().contains(lower)
        }
    }

    // MARK: - URL scheme / hotkey command execution

    /// Runs a `webcamcontroller://` command (or a hotkey / Shortcuts action) against the selected camera and
    /// returns a short status line, which is also published as `statusMessage`.
    @discardableResult
    public func execute(_ command: ControllerURLCommand, cameraSelector: String? = nil) -> String {
        let message = run(command, cameraSelector: cameraSelector)
        statusMessage = message
        DiagnosticsLogger.note("Command: \(message)")
        return message
    }

    private func run(_ command: ControllerURLCommand, cameraSelector: String?) -> String {
        var selector = cameraSelector
        if case let .camera(name) = command { selector = name }

        if let selector {
            guard let cam = findCamera(matching: selector) else {
                return "Camera not found: \(selector)"
            }
            if selectedCameraRuntimeID != cam.identity.runtimeID {
                selectedCameraRuntimeID = cam.identity.runtimeID
            }
        }

        switch command {
        case .camera:
            return selectedCamera.map { "Selected \($0.identity.productName)" } ?? "No camera available"

        case let .configuration(action):
            let target: Bool
            switch action {
            case .on: target = true
            case .off: target = false
            case .toggle: target = !isConfigurationEnabled
            }
            setConfigurationEnabled(target)
            return target ? "Configuration ON" : "Configuration OFF"

        case let .lock(on):
            isHardwareLockEnabled = on
            return on ? "Hardware Lock ON" : "Hardware Lock OFF"

        case .reset:
            guard let cam = selectedCamera else { return "No camera available" }
            cam.resetAllToHardwareDefaults()
            return "Restored factory defaults on \(cam.identity.productName)"

        case .resetView:
            guard let cam = selectedCamera else { return "No camera available" }
            cam.resetViewToDefaults()
            return "Reset view (Zoom, Pan, Tilt) on \(cam.identity.productName)"

        case .resetImage:
            guard let cam = selectedCamera else { return "No camera available" }
            cam.resetImageToDefaults()
            return "Reset image controls on \(cam.identity.productName)"

        case let .look(phrase):
            guard let cam = selectedCamera else { return "No camera available" }
            return cam.applyLook(phrase)

        case let .preset(name):
            guard selectedCamera != nil else { return "No camera available" }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower == "default" || lower == "camera default" {
                selectAndApplyPreset(selectionID: Self.cameraDefaultPresetSentinel)
                return "Restored Camera Default settings"
            }
            let presets = presetsForSelectedCamera
            let match = presets.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
                ?? Int(trimmed).flatMap { presets.indices.contains($0 - 1) ? presets[$0 - 1] : nil }
            guard let match else { return "No preset named \(trimmed)" }
            selectAndApplyPreset(selectionID: match.id.uuidString)
            return "Applied preset '\(match.name)'"

        case let .set(assignments):
            guard let cam = selectedCamera else { return "No camera available" }
            var applied: [String] = []
            for assignment in assignments {
                do {
                    let readout = try cam.writeControl(assignment.control, rawValue: assignment.value)
                    applied.append("\(readout.id)=\(readout.formattedDisplay)")
                } catch {
                    return "\(error)"
                }
            }
            return "Set " + applied.joined(separator: ", ")
        }
    }

    // MARK: - Preset export / import

    /// Writes every saved preset (all cameras) to `url` as portable JSON. Returns the number of presets exported.
    @discardableResult
    public func exportPresets(to url: URL) throws -> Int {
        let data = try presetStore.exportData()
        try data.write(to: url, options: .atomic)
        return presetStore.loadAll().count
    }

    /// Imports presets from a JSON file produced by `exportPresets`. Returns the number of presets added.
    @discardableResult
    public func importPresets(from url: URL) throws -> Int {
        let count = try presetStore.importData(Data(contentsOf: url))
        reloadPresetsForSelectedCamera()
        statusMessage = "Imported \(count) preset\(count == 1 ? "" : "s")"
        return count
    }
}
