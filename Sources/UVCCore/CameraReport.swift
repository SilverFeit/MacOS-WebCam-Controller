import Foundation

/// A paste-ready Markdown report of one camera's identity, USB link, descriptor units, supported controls and
/// stream modes. This is what a "support my camera" GitHub issue needs.
public enum CameraReport {
    @MainActor
    public static func markdown(for camera: UVCCameraDevice, appVersion: String = AppBuildInfo.currentVersion) -> String {
        let id = camera.identity
        var out: [String] = [
            "### Camera",
            "",
            "- Name: \(id.productName)",
            "- Vendor: \(id.vendorName.isEmpty ? "n/a" : id.vendorName)",
            "- USB ID: \(id.vidPidHex)",
            "- Firmware (bcdDevice): \(id.firmwareHex)",
            "- UVC version: \(id.uvcVersionString)",
            "- USB link: \(id.usbSpeedTitle)" + (id.usbSpecBCD != 0 ? String(format: " (bcdUSB 0x%04X)", id.usbSpecBCD) : ""),
            "- WebCam Controller: v\(appVersion)",
            "- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
        ]
        if let warning = id.usbLinkWarning {
            out.append("- ⚠︎ \(warning)")
        }

        out += ["", "### Descriptor", ""]
        out.append("- VideoControl interface: \(id.videoControlInterfaceNumber)")
        out.append("- Camera terminal: id \(id.cameraTerminalId)")
        out.append("- Processing unit: id \(id.processingUnitId)")
        if id.extensionUnits.isEmpty {
            out.append("- Extension units: none")
        } else {
            for xu in id.extensionUnits {
                out.append(String(
                    format: "- Extension unit: id %d, `%@`, %d controls, bitmap 0x%llx",
                    Int(xu.unitId), xu.guidString.lowercased(), Int(xu.controlCount), xu.controlsBitmap
                ))
            }
        }

        let controls = camera.readAllSupportedControls()
        out += ["", "### Supported controls", ""]
        if controls.isEmpty {
            out.append("No standard UVC controls are exposed.")
        } else {
            out += ["| Control | Min | Max | Step | Default | Current |", "| --- | --- | --- | --- | --- | --- |"]
            for c in controls {
                func cell(_ v: Int?) -> String { v.map(String.init) ?? "-" }
                out.append("| \(c.id) | \(cell(c.minimum)) | \(cell(c.maximum)) | \(cell(c.step)) | \(c.defaultValue ?? "-") | \(c.currentValue) |")
            }
        }

        out += ["", "### Video modes", ""]
        if camera.streamModes.isEmpty {
            out.append("No UVC VideoStreaming descriptors exposed.")
        } else {
            for codec in camera.availableStreamCodecs {
                for mode in UVCStreamValidator.resolutions(for: codec, in: camera.streamModes) {
                    let fps = mode.supportedFPS.map { String($0.fps) }.joined(separator: ", ")
                    out.append("- \(codec.shortTitle) \(mode.width)×\(mode.height): \(fps) fps (default \(mode.defaultFPS))")
                }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Pre-filled bug report form, to paste the report into.
    public static var issueURL: URL {
        URL(string: "https://github.com/\(AppBuildInfo.githubOwner)/\(AppBuildInfo.githubRepo)/issues/new?template=bug_report.yml")!
    }
}
