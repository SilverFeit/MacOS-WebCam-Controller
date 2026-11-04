import Foundation
import UVCCore

private let cliUsage = """
webcamctl — Direct USB UVC Hardware CLI for MacOS WebCam Controller

USAGE:
  webcamctl <command> [arguments] [--camera <index|id|name>] [--json]

COMMANDS:
  list                                   List connected USB UVC webcams
  describe [--raw]                       Show UVC units, extension GUIDs, controls & video modes
  get [control...]                       Read live hardware controls (all supported when omitted)
  set <control>=<value>...               Write hardware registers or video stream modes
                                           Examples:
                                             webcamctl set exposure_mode=manual shutter=1/60 gain=18
                                             webcamctl set kelvin=4500 brightness=+8 zoom=130
                                             webcamctl set resolution=2560x1440 fps=30 format=mjpeg
  reset [control...]                     Rollback specific control(s) or all to factory default (GET_DEF)
  stream [list|get|set <WxH> [fps] [fmt]|reset]
                                         Inspect or negotiate UVC VideoStreaming resolution & FPS
  preset list                            List saved presets for the target camera
  preset save <name> [--startup]         Save current hardware state as a named preset
  preset apply <name>                    Apply a saved preset (or 'default') to hardware
  preset delete <name>                   Delete a saved preset
  lock [on|off|status]                   Control or inspect the Anti-Reset Hardware Lock
  who                                    Show active camera streams & likely video call apps
  sessions [--clear]                     Show recent camera call session history
  check-update                           Check GitHub Releases for a newer version
  version                                Print current version

GLOBAL OPTIONS:
  --camera, -c <selector>                Select camera by index (0), VID:PID, serial, or name substring
  --json                                 Output machine-readable JSON for scripting / Shortcuts / Raycast
  --help, -h                             Show this help message
"""

private struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}

private func printJSONObject(_ obj: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
}

@MainActor
private struct WebcamCTL {
    static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())

        func takeFlag(_ names: String...) -> Bool {
            if let idx = args.firstIndex(where: { names.contains($0) }) {
                args.remove(at: idx)
                return true
            }
            return false
        }

        func takeOption(_ names: String...) -> String? {
            guard let idx = args.firstIndex(where: { names.contains($0) }), idx + 1 < args.count else {
                return nil
            }
            let val = args[idx + 1]
            args.removeSubrange(idx...(idx + 1))
            return val
        }

        let jsonOutput = takeFlag("--json")
        let cameraSelector = takeOption("--camera", "-c")

        guard let command = args.first else {
            print(cliUsage)
            return
        }
        args.removeFirst()

        switch command {
        case "help", "--help", "-h":
            print(cliUsage)

        case "version", "--version", "-v":
            if jsonOutput {
                try printJSONObject([
                    "version": AppBuildInfo.currentVersion,
                    "repository": AppBuildInfo.repositoryURL.absoluteString,
                    "homebrew": AppBuildInfo.homebrewInstallCommand
                ])
            } else {
                print("webcamctl \(AppBuildInfo.currentVersion) (\(AppBuildInfo.repositoryURL.absoluteString))")
            }

        case "check-update", "update":
            try await handleCheckUpdate(json: jsonOutput)

        case "who":
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            let uvcIdentities = manager.cameras.map(\.identity)
            let activities = CameraActivityMonitor.allCameraActivities(matchingUVCIdentities: uvcIdentities)
            let audioUsers = CameraActivityMonitor.audioInputCapturingApps()
            let likelyUsers = CameraActivityMonitor.likelyCameraUsers()

            if jsonOutput {
                try printJSONObject([
                    "cameras": activities.map { a in
                        [
                            "id": a.id,
                            "name": a.name,
                            "uvc": a.isUVC,
                            "built_in": a.isBuiltIn,
                            "streaming": a.isStreamingSomewhere
                        ] as [String: Any]
                    },
                    "audio_input_apps": audioUsers.map { ["name": $0.name, "bundle_id": $0.bundleID ?? ""] },
                    "likely_camera_apps": likelyUsers.map {
                        ["name": $0.name, "bundle_id": $0.bundleID ?? "", "evidence": $0.evidence.rawValue]
                    }
                ])
            } else {
                if activities.isEmpty {
                    print("No cameras detected on macOS.")
                } else {
                    for cam in activities {
                        let tag = cam.isUVC ? "USB UVC" : (cam.isBuiltIn ? "Built-in" : "External")
                        let state = cam.isStreamingSomewhere ? "STREAMING" : "idle"
                        print("[\(state)] \(cam.name) (\(tag))")
                    }
                }
                let audioNames = audioUsers.isEmpty ? "none" : audioUsers.map(\.name).joined(separator: ", ")
                print("Apps capturing audio input : \(audioNames)")
                if activities.contains(where: \.isStreamingSomewhere) {
                    let likelyText = likelyUsers.isEmpty
                        ? "unknown"
                        : likelyUsers.map { "\($0.name) (\($0.evidence.rawValue))" }.joined(separator: ", ")
                    print("Likely active camera app(s): \(likelyText)")
                }
            }

        case "sessions":
            let clear = takeFlag("--clear")
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            if clear {
                manager.clearCallSessionHistory()
                CameraManager.postExternalSyncNotification()
                if jsonOutput {
                    try printJSONObject(["cleared": true])
                } else {
                    print("Cleared recorded camera call sessions.")
                }
                return
            }
            let formatter = ISO8601DateFormatter()
            if jsonOutput {
                try printJSONObject(manager.recentCallSessions.map { s in
                    var item: [String: Any] = [
                        "app": s.appNames,
                        "camera": s.cameraName,
                        "started_at": formatter.string(from: s.startedAt),
                        "duration_seconds": s.durationSeconds,
                        "stream": s.streamSummary
                    ]
                    if let fixed = s.autoUpgradedFromSlowMode {
                        item["upgraded_slow_mode_from"] = fixed
                    }
                    return item
                })
            } else if manager.recentCallSessions.isEmpty {
                print("No recorded camera call sessions yet.")
            } else {
                for s in manager.recentCallSessions {
                    let fixedNote = s.autoUpgradedFromSlowMode.map { " [fixed from \($0)]" } ?? ""
                    print("\(formatter.string(from: s.startedAt))  \(s.appNames)  ·  \(s.cameraName)  ·  \(s.streamSummary)  (\(s.durationSeconds)s)\(fixedNote)")
                }
            }

        case "list":
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            if jsonOutput {
                try printJSONObject(manager.cameras.enumerated().map { idx, cam in
                    let id = cam.identity
                    return [
                        "index": idx,
                        "name": id.productName,
                        "vendor_name": id.vendorName,
                        "vendor_id": String(format: "0x%04x", id.vendorId),
                        "product_id": String(format: "0x%04x", id.productId),
                        "firmware": id.firmwareHex,
                        "uvc_version": id.uvcVersionString,
                        "serial": id.serialNumber,
                        "location_id": id.locationHex,
                        "persistent_id": id.persistentID,
                        "streaming": cam.isHardwareStreamingActive
                    ] as [String: Any]
                })
            } else if manager.cameras.isEmpty {
                print("No external USB UVC webcams found.")
            } else {
                for (idx, cam) in manager.cameras.enumerated() {
                    let id = cam.identity
                    let sn = id.serialNumber.isEmpty ? "n/a" : id.serialNumber
                    print(String(
                        format: "[%d] %@  %@  serial=%@  fw=%@  uvc=%@  id=%@",
                        idx, id.productName, id.vidPidHex, sn, id.firmwareHex, id.uvcVersionString, id.persistentID
                    ))
                }
            }

        case "describe":
            let rawFlag = takeFlag("--raw")
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            let cam = try selectTargetCamera(in: manager, selector: cameraSelector)
            if rawFlag {
                guard let rawBytes = cam.copyRawConfigurationDescriptor() else {
                    throw CLIError("unable to read raw USB configuration descriptor")
                }
                let hex = rawBytes.map { String(format: "%02x", $0) }.joined()
                if jsonOutput {
                    try printJSONObject(["length": rawBytes.count, "descriptor_hex": hex])
                } else {
                    print(hex)
                }
                return
            }

            let id = cam.identity
            let supportedControls = cam.readAllSupportedControls()
            if jsonOutput {
                try printJSONObject([
                    "name": id.productName,
                    "vendor_product": id.vidPidHex,
                    "firmware": id.firmwareHex,
                    "uvc_version": id.uvcVersionString,
                    "vc_interface": id.videoControlInterfaceNumber,
                    "camera_terminal_id": id.cameraTerminalId,
                    "processing_unit_id": id.processingUnitId,
                    "extension_units": id.extensionUnits.map { xu in
                        [
                            "unit_id": xu.unitId,
                            "guid": xu.guidString,
                            "control_count": xu.controlCount,
                            "controls_bitmap": String(format: "0x%llx", xu.controlsBitmap),
                            "title": xu.knownVendorTitle ?? "Vendor Extension Unit"
                        ] as [String: Any]
                    },
                    "supported_controls": supportedControls.map(\.id),
                    "stream_modes": cam.streamModes.map { m in
                        [
                            "codec": m.codec.shortTitle,
                            "width": m.width,
                            "height": m.height,
                            "default_fps": m.defaultFPS,
                            "supported_fps": m.supportedFPS.map(\.fps)
                        ] as [String: Any]
                    }
                ])
            } else {
                print("\(id.productName)  [\(id.vidPidHex)]  FW \(id.firmwareHex)  UVC \(id.uvcVersionString)")
                print("VideoControl Ifc #\(id.videoControlInterfaceNumber)  ·  CameraTerminal ID=\(id.cameraTerminalId)  ·  ProcessingUnit ID=\(id.processingUnitId)")
                for xu in id.extensionUnits {
                    let label = xu.knownVendorTitle ?? "Vendor Extension Unit"
                    print("ExtensionUnit   ID=\(xu.unitId)  \(xu.guidString)  (\(xu.controlCount) controls · \(label))")
                }
                print("Supported UVC Controls (\(supportedControls.count)): \(supportedControls.map(\.id).joined(separator: ", "))")
                if !cam.streamModes.isEmpty {
                    print("VideoStreaming Formats & Validated FPS:")
                    for codec in cam.availableStreamCodecs {
                        let modes = UVCStreamValidator.resolutions(for: codec, in: cam.streamModes)
                        for m in modes {
                            let fpsList = m.supportedFPS.map { "\($0.fps)" }.joined(separator: ", ")
                            print("  - \(codec.shortTitle.padding(toLength: 6, withPad: " ", startingAt: 0)) \(m.displayTitle.padding(toLength: 22, withPad: " ", startingAt: 0)) FPS: [\(fpsList)] (default \(m.defaultFPS))")
                        }
                    }
                }
            }

        case "get":
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            let cam = try selectTargetCamera(in: manager, selector: cameraSelector)
            let readouts: [UVCControlReadout]
            if args.isEmpty || args == ["all"] {
                readouts = cam.readAllSupportedControls()
            } else {
                readouts = try args.map { try cam.readControl($0) }
            }
            if jsonOutput {
                try printJSONObject(readouts.map { $0.toJSONObject() })
            } else {
                for r in readouts {
                    print(r.formattedCLILine())
                }
            }

        case "set":
            guard !args.isEmpty else {
                throw CLIError("`set` requires one or more <control>=<value> arguments (e.g. `webcamctl set kelvin=4500 shutter=1/60`)")
            }
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            let cam = try selectTargetCamera(in: manager, selector: cameraSelector)

            var updated: [UVCControlReadout] = []
            for token in args {
                let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    throw CLIError("expected <control>=<value>, got '\(token)'")
                }
                let res = try cam.writeControl(parts[0], rawValue: parts[1])
                updated.append(res)
            }
            CameraManager.postExternalSyncNotification()

            if jsonOutput {
                try printJSONObject(updated.map { $0.toJSONObject() })
            } else {
                for r in updated {
                    print(r.formattedCLILine())
                }
            }

        case "reset":
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            let cam = try selectTargetCamera(in: manager, selector: cameraSelector)

            if args.isEmpty || args == ["all"] {
                cam.resetAllToHardwareDefaults()
                CameraManager.postExternalSyncNotification()
                let all = cam.readAllSupportedControls()
                if jsonOutput {
                    try printJSONObject(all.map { $0.toJSONObject() })
                } else {
                    print("Restored all hardware registers to factory defaults (GET_DEF):")
                    for r in all {
                        print(r.formattedCLILine())
                    }
                }
            } else {
                var results: [UVCControlReadout] = []
                for key in args {
                    results.append(try cam.resetControl(key))
                }
                CameraManager.postExternalSyncNotification()
                if jsonOutput {
                    try printJSONObject(results.map { $0.toJSONObject() })
                } else {
                    for r in results {
                        print(r.formattedCLILine())
                    }
                }
            }

        case "stream":
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            let cam = try selectTargetCamera(in: manager, selector: cameraSelector)
            let sub = args.first ?? "get"
            switch sub {
            case "list":
                if jsonOutput {
                    try printJSONObject(cam.streamModes.map { m in
                        [
                            "codec": m.codec.shortTitle,
                            "width": m.width,
                            "height": m.height,
                            "default_fps": m.defaultFPS,
                            "supported_fps": m.supportedFPS.map(\.fps)
                        ] as [String: Any]
                    })
                } else if cam.streamModes.isEmpty {
                    print("Camera does not advertise UVC VideoStreaming descriptors.")
                } else {
                    for codec in cam.availableStreamCodecs {
                        for m in UVCStreamValidator.resolutions(for: codec, in: cam.streamModes) {
                            let fpsList = m.supportedFPS.map { "\($0.fps)" }.joined(separator: ", ")
                            print("\(codec.shortTitle.padding(toLength: 6, withPad: " ", startingAt: 0)) \(m.displayTitle.padding(toLength: 22, withPad: " ", startingAt: 0)) FPS: [\(fpsList)]")
                        }
                    }
                }
            case "get":
                let r = try cam.readControl("stream")
                if jsonOutput {
                    try printJSONObject(r.toJSONObject())
                } else {
                    print(r.formattedCLILine())
                    if !cam.streamStatusNote.isEmpty {
                        print("Status: \(cam.streamStatusNote)")
                    }
                }
            case "reset":
                let r = try cam.resetControl("stream")
                CameraManager.postExternalSyncNotification()
                if jsonOutput {
                    try printJSONObject(r.toJSONObject())
                } else {
                    print(r.formattedCLILine())
                }
            case "set":
                let rest = Array(args.dropFirst())
                guard let resToken = rest.first, let (w, h) = UVCCameraDevice.parseResolutionToken(resToken) else {
                    throw CLIError("usage: webcamctl stream set <WxH|2k|1080p|720p> [fps] [mjpeg|yuy2|h264]")
                }
                let fpsVal = rest.count >= 2 ? Int(rest[1].lowercased().replacingOccurrences(of: "fps", with: "")) : nil
                let codecVal = rest.count >= 3 ? UVCCameraDevice.parseCodecToken(rest[2]) : nil
                let targetCodec = codecVal ?? cam.selectedStream?.codec ?? cam.availableStreamCodecs.first ?? .mjpeg
                let targetFPS = fpsVal ?? cam.selectedStream?.fps ?? 30
                guard let validated = UVCStreamValidator.validateSelection(
                    modes: cam.streamModes,
                    desiredCodec: targetCodec,
                    desiredWidth: w,
                    desiredHeight: h,
                    desiredFPS: targetFPS
                ), cam.applyStreamSelection(validated) else {
                    throw CLIError("stream \(w)x\(h) @ \(targetFPS)fps (\(targetCodec.shortTitle)) could not be applied")
                }
                CameraManager.postExternalSyncNotification()
                if jsonOutput {
                    try printJSONObject([
                        "stream": validated.detailedSummary,
                        "status": cam.streamStatusNote
                    ])
                } else {
                    print(cam.streamStatusNote)
                }
            default:
                throw CLIError("unknown stream subcommand '\(sub)' (expected list, get, set, or reset)")
            }

        case "preset":
            let startupFlag = takeFlag("--startup", "--load-at-start")
            guard let sub = args.first else {
                throw CLIError("usage: webcamctl preset <list|save|apply|delete> [name]")
            }
            let presetName = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            let cam = try selectTargetCamera(in: manager, selector: cameraSelector)
            manager.selectedCameraRuntimeID = cam.identity.runtimeID

            switch sub {
            case "list":
                let presets = manager.presetsForSelectedCamera
                if jsonOutput {
                    try printJSONObject(presets.map {
                        ["name": $0.name, "load_at_start": $0.loadAtStart, "id": $0.id.uuidString] as [String: Any]
                    })
                } else if presets.isEmpty {
                    print("No saved presets for \(cam.identity.productName).")
                } else {
                    for p in presets {
                        let star = p.loadAtStart ? " ★ (Load at Start)" : ""
                        print("- \(p.name)\(star)")
                    }
                }
            case "save":
                guard !presetName.isEmpty else { throw CLIError("`preset save` requires a preset name") }
                guard let saved = manager.saveCurrentSettingsAsPreset(name: presetName, loadAtStart: startupFlag) else {
                    throw CLIError("failed to save preset")
                }
                CameraManager.postExternalSyncNotification()
                if jsonOutput {
                    try printJSONObject(["saved": saved.name, "load_at_start": saved.loadAtStart])
                } else {
                    print("Saved preset '\(saved.name)' for \(cam.identity.productName)\(saved.loadAtStart ? " (Load at Start)" : "").")
                }
            case "apply":
                guard !presetName.isEmpty else { throw CLIError("`preset apply` requires a preset name (or 'default')") }
                if presetName.lowercased() == "default" || presetName.lowercased() == "camera default" {
                    cam.resetAllToHardwareDefaults()
                    CameraManager.postExternalSyncNotification()
                    if jsonOutput {
                        try printJSONObject(["applied": "Camera Default"])
                    } else {
                        print("Restored Camera Default settings on \(cam.identity.productName).")
                    }
                } else {
                    guard let match = manager.presetsForSelectedCamera.first(where: {
                        $0.name.caseInsensitiveCompare(presetName) == .orderedSame
                    }) else {
                        throw CLIError("no preset named '\(presetName)' for \(cam.identity.productName)")
                    }
                    manager.selectAndApplyPreset(selectionID: match.id.uuidString)
                    CameraManager.postExternalSyncNotification()
                    if jsonOutput {
                        try printJSONObject(["applied": match.name])
                    } else {
                        print("Applied preset '\(match.name)' to \(cam.identity.productName).")
                    }
                }
            case "delete":
                guard !presetName.isEmpty else { throw CLIError("`preset delete` requires a preset name") }
                guard let match = manager.presetsForSelectedCamera.first(where: {
                    $0.name.caseInsensitiveCompare(presetName) == .orderedSame
                }) else {
                    throw CLIError("no preset named '\(presetName)'")
                }
                manager.presetStore.deletePreset(id: match.id)
                CameraManager.postExternalSyncNotification()
                if jsonOutput {
                    try printJSONObject(["deleted": match.name])
                } else {
                    print("Deleted preset '\(match.name)'.")
                }
            default:
                throw CLIError("unknown preset subcommand '\(sub)' (expected list, save, apply, or delete)")
            }

        case "lock":
            let sub = args.first?.lowercased() ?? "status"
            let manager = CameraManager(enableHotplugWatcher: false, enableBackgroundMonitors: false)
            defer { manager.shutdown() }
            switch sub {
            case "on", "enable", "true", "1":
                manager.isHardwareLockEnabled = true
                CameraManager.postExternalSyncNotification()
            case "off", "disable", "false", "0":
                manager.isHardwareLockEnabled = false
                CameraManager.postExternalSyncNotification()
            case "status":
                break
            default:
                throw CLIError("expected `webcamctl lock [on|off|status]`")
            }
            if jsonOutput {
                try printJSONObject(["hardware_lock": manager.isHardwareLockEnabled])
            } else {
                print("Anti-Reset Hardware Lock: \(manager.isHardwareLockEnabled ? "ON" : "OFF")")
            }

        default:
            throw CLIError("unknown command '\(command)'\n\n\(cliUsage)")
        }
    }

    private static func selectTargetCamera(in manager: CameraManager, selector: String?) throws -> UVCCameraDevice {
        guard !manager.cameras.isEmpty else {
            throw CLIError("no external USB UVC webcam connected")
        }
        guard let sel = selector?.trimmingCharacters(in: .whitespacesAndNewlines), !sel.isEmpty else {
            if let active = manager.selectedCamera {
                return active
            }
            return manager.cameras[0]
        }
        if let idx = Int(sel), manager.cameras.indices.contains(idx) {
            return manager.cameras[idx]
        }
        let lower = sel.lowercased()
        if let match = manager.cameras.first(where: { cam in
            let id = cam.identity
            return id.persistentID.lowercased() == lower
                || id.runtimeID.lowercased() == lower
                || id.modelKey.lowercased() == lower
                || id.vidPidHex.lowercased() == lower
                || (!id.serialNumber.isEmpty && id.serialNumber.lowercased() == lower)
                || id.productName.lowercased().contains(lower)
        }) {
            return match
        }
        throw CLIError("no attached UVC camera matches '\(sel)' (run `webcamctl list`)")
    }

    private static func handleCheckUpdate(json: Bool) async throws {
        let localVer = AppBuildInfo.currentVersion
        let localSem = AppBuildInfo.currentSemanticVersion
        do {
            let remote = try await UpdateChecker.fetchLatestGitHubRelease()
            let remoteSem = remote.semanticVersion
            let updateAvailable = remoteSem.map { $0 > localSem } ?? false
            if jsonOutput(json, payload: [
                "current_version": localVer,
                "latest_version": remote.versionString,
                "tag": remote.tagName,
                "update_available": updateAvailable,
                "release_url": remote.htmlURL.absoluteString,
                "brew_upgrade": AppBuildInfo.homebrewUpgradeCommand
            ]) {
                return
            }
            if updateAvailable {
                print("Update available: v\(localVer) -> v\(remote.versionString)")
                print("Upgrade via Homebrew : \(AppBuildInfo.homebrewUpgradeCommand)")
                print("GitHub Release       : \(remote.htmlURL.absoluteString)")
            } else {
                print("MacOS WebCam Controller is up to date (v\(localVer)).")
                print("GitHub Releases: \(remote.htmlURL.absoluteString)")
            }
        } catch {
            if json {
                try printJSONObject([
                    "current_version": localVer,
                    "update_available": false,
                    "error": error.localizedDescription,
                    "releases_url": AppBuildInfo.releasesPageURL.absoluteString
                ])
            } else {
                print("Installed version: v\(localVer)")
                print("Could not reach GitHub Releases API (\(error.localizedDescription)).")
                print("Check manually: \(AppBuildInfo.releasesPageURL.absoluteString)")
            }
        }
    }

    private static func jsonOutput(_ enabled: Bool, payload: [String: Any]) -> Bool {
        guard enabled else { return false }
        try? printJSONObject(payload)
        return true
    }
}

@main
struct WebcamCTLEntry {
    static func main() async {
        do {
            try await WebcamCTL.run()
        } catch {
            FileHandle.standardError.write(Data("webcamctl: \(error)\n".utf8))
            exit(1)
        }
    }
}
