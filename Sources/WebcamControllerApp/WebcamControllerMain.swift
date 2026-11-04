import AppKit
import Foundation
import UVCCore

@main
struct WebcamControllerMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--dump-hardware") {
            runHardwareDiagnosticDump()
            return
        }
        if let idx = args.firstIndex(of: "--render-docs-assets"), idx + 1 < args.count {
            do {
                try DocAssetRenderer.generateAllAssets(outputDirectory: args[idx + 1])
                return
            } catch {
                fputs("Failed to render documentation assets: \(error)\n", stderr)
                exit(1)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        if args.contains("--open-advanced") {
            DispatchQueue.main.async {
                delegate.openSettingsPanel(tab: .advanced)
            }
        } else if args.contains("--open-panel") {
            DispatchQueue.main.async {
                delegate.openSettingsPanel(tab: .basic)
            }
        }

        app.run()
    }

    @MainActor
    private static func runHardwareDiagnosticDump() {
        let manager = CameraManager(enableHotplugWatcher: false)
        print("=== WebCam Controller UVC Hardware Diagnostic ===")
        print("Detected UVC USB Cameras: \(manager.cameras.count)")
        for (idx, cam) in manager.cameras.enumerated() {
            let id = cam.identity
            print("[\(idx)] \(id.productName)")
            print("    Vendor/Product : \(id.vidPidHex) (\(id.vendorName))")
            print("    Location/Serial: \(id.locationHex) / \(id.serialNumber)")
            print("    Persistent ID  : \(id.persistentID)")
            print("    UVC Spec       : \(id.uvcVersionString) (Ifc #\(id.videoControlInterfaceNumber), CT=\(id.cameraTerminalId), PU=\(id.processingUnitId))")
            print("    AE Mode        : supported=\(cam.autoExposureMode.isSupported) mask=\(cam.autoExposureMode.supportedBitmask) cur=\(cam.autoExposureMode.current.title)")
            print("    Exposure Time  : supported=\(cam.exposureTime.isSupported) [\(cam.exposureTime.minimum)...\(cam.exposureTime.maximum)] cur=\(cam.exposureTime.current) def=\(cam.exposureTime.defaultValue)")
            print("    Gain           : supported=\(cam.gain.isSupported) [\(cam.gain.minimum)...\(cam.gain.maximum)] cur=\(cam.gain.current)")
            print("    Brightness     : supported=\(cam.brightness.isSupported) [\(cam.brightness.minimum)...\(cam.brightness.maximum)] cur=\(cam.brightness.current) def=\(cam.brightness.defaultValue)")
            print("    Contrast       : supported=\(cam.contrast.isSupported) [\(cam.contrast.minimum)...\(cam.contrast.maximum)] cur=\(cam.contrast.current) def=\(cam.contrast.defaultValue)")
            print("    Hue            : supported=\(cam.hue.isSupported) [\(cam.hue.minimum)...\(cam.hue.maximum)] cur=\(cam.hue.current) def=\(cam.hue.defaultValue)")
            print("    Saturation     : supported=\(cam.saturation.isSupported) [\(cam.saturation.minimum)...\(cam.saturation.maximum)] cur=\(cam.saturation.current) def=\(cam.saturation.defaultValue)")
            print("    Sharpness      : supported=\(cam.sharpness.isSupported) [\(cam.sharpness.minimum)...\(cam.sharpness.maximum)] cur=\(cam.sharpness.current) def=\(cam.sharpness.defaultValue)")
            print("    Gamma          : supported=\(cam.gamma.isSupported) [\(cam.gamma.minimum)...\(cam.gamma.maximum)] cur=\(cam.gamma.current) def=\(cam.gamma.defaultValue)")
            print("    WB Auto / Temp : auto=\(cam.whiteBalanceAuto.current) temp=[\(cam.whiteBalanceTemperature.minimum)...\(cam.whiteBalanceTemperature.maximum)] cur=\(cam.whiteBalanceTemperature.current)K")
            print("    Anti-Flicker   : supported=\(cam.powerLineFrequency.isSupported) [\(cam.powerLineFrequency.minimum)...\(cam.powerLineFrequency.maximum)] cur=\(cam.powerLineFrequency.current)")
            print("    Backlight Comp : supported=\(cam.backlightCompensation.isSupported) [\(cam.backlightCompensation.minimum)...\(cam.backlightCompensation.maximum)] cur=\(cam.backlightCompensation.current)")
            print("    Low-Light Prio : supported=\(cam.autoExposurePriority.isSupported) cur=\(cam.autoExposurePriority.current)")
            print("    Focus          : supported=\(cam.focusAbsolute.isSupported) auto=\(cam.focusAuto.isSupported)")
            print("    Zoom/Pan/Tilt  : zoom=\(cam.zoomAbsolute.isSupported) pan=\(cam.panAbsolute.isSupported) tilt=\(cam.tiltAbsolute.isSupported)")
            if let defStream = cam.defaultStream, let selStream = cam.selectedStream {
                print("    Video Stream   : selected=\(selStream.detailedSummary) default=\(defStream.detailedSummary) activePipe=\(cam.isHardwareStreamingActive)")
            }
            for codec in cam.availableStreamCodecs {
                let resModes = UVCStreamValidator.resolutions(for: codec, in: cam.streamModes)
                let summary = resModes.map { m in
                    let fpsStr = m.supportedFPS.map { "\($0.fps)" }.joined(separator: "/")
                    return "\(m.width)x\(m.height)@[\(fpsStr)]fps"
                }.joined(separator: ", ")
                print("    Modes (\(codec.shortTitle))   : \(summary)")
            }
        }
        manager.shutdown()
    }
}
