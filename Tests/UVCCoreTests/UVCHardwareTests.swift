import Foundation
import CUVCHardware
import UVCCore

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        self.description = "\(file):\(line) — \(message)"
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Assertion failed", file: StaticString = #fileID, line: UInt = #line) throws {
    if !condition() {
        throw TestFailure(message, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String = "", file: StaticString = #fileID, line: UInt = #line) throws {
    if actual != expected {
        let prefix = label.isEmpty ? "" : "[\(label)] "
        throw TestFailure("\(prefix)Expected \(expected), got \(actual)", file: file, line: line)
    }
}

@main
struct UVCHardwareTestSuite {
    @MainActor
    static func main() {
        print("===============================================================")
        print(" WebCam Controller — Unit & Live USB Hardware Test Suite")
        print("===============================================================")

        var passed = 0
        var failed = 0

        func runTest(_ name: String, block: @MainActor () throws -> Void) {
            do {
                try block()
                passed += 1
                print("  [PASS] \(name)")
            } catch {
                failed += 1
                print("  [FAIL] \(name)\n         -> \(error)")
            }
        }

        runTest("1. Auto-Exposure Mode UVC 1.5 Bitmask Decoding") {
            let modes9 = AutoExposureMode.supportedModes(fromBitmask: 9)
            try expectEqual(modes9, [.manual, .aperturePriority], "Bitmask 9")

            let state = AutoExposureModeState(
                isSupported: true,
                canSet: true,
                supportedBitmask: 9,
                defaultMode: .aperturePriority,
                current: .aperturePriority
            )
            try expect(state.isModeSupported(.manual), "Manual supported")
            try expect(!state.isModeSupported(.auto), "Auto unsupported")
            try expect(!state.isModeSupported(.shutterPriority), "Shutter unsupported")
            try expect(state.isModeSupported(.aperturePriority), "Aperture supported")
            try expect(!state.allowsManualExposureTime, "Aperture Priority locks manual exposure time")
        }

        runTest("2. NumericRangeControlState Signed/Unsigned Clamping & Step Snapping") {
            let signedBrightness = NumericRangeControlState(
                isSupported: true,
                canSet: true,
                minimum: -64,
                maximum: 64,
                step: 1,
                defaultValue: 3,
                current: 3
            )
            try expectEqual(signedBrightness.clampedAndSnapped(-100), -64)
            try expectEqual(signedBrightness.clampedAndSnapped(200), 64)
            try expectEqual(signedBrightness.clampedAndSnapped(-15), -15)

            let kelvinStep10 = NumericRangeControlState(
                isSupported: true,
                canSet: true,
                minimum: 2800,
                maximum: 6500,
                step: 10,
                defaultValue: 4600,
                current: 4600
            )
            try expectEqual(kelvinStep10.clampedAndSnapped(3804), 3800)
            try expectEqual(kelvinStep10.clampedAndSnapped(3806), 3810)
        }

        runTest("3. CameraIdentity Persistent ID & USB Port Relocation Matching") {
            let camPortA = CameraIdentity(
                vendorId: 0x041e,
                productId: 0x40a3,
                locationId: 0x00110000,
                uvcVersionBCD: 0x0100,
                videoControlInterfaceNumber: 0,
                cameraTerminalId: 1,
                processingUnitId: 2,
                productName: "Creative Live! Cam Sync V3",
                vendorName: "Creative Technology Ltd",
                serialNumber: "SN0001"
            )
            try expectEqual(camPortA.persistentID, "041e:40a3:SN0001")
            try expectEqual(camPortA.vidPidHex, "0x041e:0x40a3")
            try expectEqual(camPortA.uvcVersionString, "1.00")
            try expect(camPortA.matchesConfiguredID("041e:40a3:SN0001"))
            try expect(camPortA.matchesConfiguredID("041e:40a3@00220000"))
            try expect(!camPortA.matchesConfiguredID("046d:082d:OTHER"))
        }

        runTest("4. PresetStore Persistence & Startup Preset Exclusivity per Camera ID") {
            let suiteName = "com.webcamcontroller.tests.\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: suiteName)!
            defer { testDefaults.removePersistentDomain(forName: suiteName) }

            let store = PresetStore(defaults: testDefaults)
            let identity = CameraIdentity(
                vendorId: 0x041e,
                productId: 0x40a3,
                locationId: 0x00110000,
                uvcVersionBCD: 0x0100,
                videoControlInterfaceNumber: 0,
                cameraTerminalId: 1,
                processingUnitId: 2,
                productName: "Creative Live! Cam Sync V3",
                vendorName: "Creative",
                serialNumber: "SN0001"
            )

            let p1 = store.upsertPreset(
                name: "Daylight",
                for: identity,
                snapshot: CameraSettingsSnapshot(brightness: 10, contrast: 40),
                loadAtStart: true
            )
            let p2 = store.upsertPreset(
                name: "Night Studio",
                for: identity,
                snapshot: CameraSettingsSnapshot(brightness: -8, whiteBalanceAuto: false, whiteBalanceTemperature: 3600),
                loadAtStart: true
            )

            try expectEqual(store.presets(for: identity).count, 2)
            try expectEqual(store.startupPreset(for: identity)?.id, p2.id)

            store.deletePreset(id: p1.id)
            try expectEqual(store.presets(for: identity).count, 1)
        }

        runTest("5. Live USB Discovery & Descriptor Introspection via IOKit Endpoint 0") {
            let suiteName = "com.webcamcontroller.livedisc.\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: suiteName)!
            defer { testDefaults.removePersistentDomain(forName: suiteName) }

            let manager = CameraManager(defaults: testDefaults, enableHotplugWatcher: false)
            defer { manager.shutdown() }

            try expect(!manager.cameras.isEmpty, "Expected at least 1 connected USB UVC webcam")
            let cam = manager.selectedCamera!
            try expect(cam.identity.vendorId != 0, "Non-zero USB Vendor ID")
            try expect(cam.identity.productId != 0, "Non-zero USB Product ID")
            try expect(cam.brightness.isSupported, "Brightness supported")
            try expect(cam.contrast.isSupported, "Contrast supported")
            try expect(cam.whiteBalanceTemperature.isSupported, "White Balance Temperature supported")
            try expect(cam.autoExposureMode.isSupported, "Auto-Exposure Mode supported")
        }

        runTest("6. Live Hardware Register Write/Readback (Brightness, Contrast, Backlight) + Anti-Reset Lock") {
            let suiteName = "com.webcamcontroller.livewrite.\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: suiteName)!
            defer { testDefaults.removePersistentDomain(forName: suiteName) }

            let manager = CameraManager(defaults: testDefaults, enableHotplugWatcher: false)
            defer { manager.shutdown() }

            guard let camera = manager.selectedCamera else {
                throw TestFailure("No USB UVC camera connected")
            }
            let id = camera.identity
            let originalSnapshot = camera.captureSnapshot()
            defer { camera.applySnapshot(originalSnapshot) }

            // A) Signed Brightness physical write & independent USB handle readback
            let origBrightness = camera.brightness.current
            let targetBrightness = (origBrightness + 9 <= camera.brightness.maximum) ? (origBrightness + 9) : (origBrightness - 9)
            try expect(camera.setBrightness(targetBrightness), "setBrightness succeeded")

            guard let vh = cuvc_open_device(id.locationId, id.vendorId, id.productId) else {
                throw TestFailure("Failed to open independent verification handle")
            }
            defer { cuvc_close_device(vh) }

            var hwBrightness: Int64 = 0
            try expect(
                cuvc_get_int(vh, UInt8(CUVC_REQ_GET_CUR.rawValue), UInt8(id.processingUnitId), UInt8(CUVC_PU_BRIGHTNESS_CONTROL.rawValue), 2, true, &hwBrightness),
                "Independent GET_CUR brightness"
            )
            try expectEqual(Int(hwBrightness), targetBrightness, "Physical ISP brightness register")

            // B) Simulate external app (Photo Booth / Zoom) resetting brightness register behind our back
            try expect(
                cuvc_set_int(vh, UInt8(id.processingUnitId), UInt8(CUVC_PU_BRIGHTNESS_CONTROL.rawValue), 2, true, Int64(origBrightness)),
                "Simulated external reset"
            )
            let restored = camera.enforceLockedSnapshotIfDrifted()
            try expect(restored >= 1, "Anti-reset daemon detected and re-injected drifted register")

            var lockedBrightness: Int64 = 0
            _ = cuvc_get_int(vh, UInt8(CUVC_REQ_GET_CUR.rawValue), UInt8(id.processingUnitId), UInt8(CUVC_PU_BRIGHTNESS_CONTROL.rawValue), 2, true, &lockedBrightness)
            try expectEqual(Int(lockedBrightness), targetBrightness, "Hardware Lock restored brightness")

            // C) Contrast + Backlight Compensation physical write & readback
            let origContrast = camera.contrast.current
            let targetContrast = (origContrast + 5 <= camera.contrast.maximum) ? (origContrast + 5) : (origContrast - 5)
            try expect(camera.setContrast(targetContrast), "setContrast succeeded")

            var hwContrast: Int64 = 0
            _ = cuvc_get_int(vh, UInt8(CUVC_REQ_GET_CUR.rawValue), UInt8(id.processingUnitId), UInt8(CUVC_PU_CONTRAST_CONTROL.rawValue), 2, false, &hwContrast)
            try expectEqual(Int(hwContrast), targetContrast, "Physical ISP contrast register")

            if camera.backlightCompensation.isSupported {
                try expect(camera.setBacklightEnabled(false), "Backlight Off")
                var hwBLC: Int64 = -1
                _ = cuvc_get_int(vh, UInt8(CUVC_REQ_GET_CUR.rawValue), UInt8(id.processingUnitId), UInt8(CUVC_PU_BACKLIGHT_COMPENSATION_CONTROL.rawValue), 2, false, &hwBLC)
                try expectEqual(Int(hwBLC), camera.backlightCompensation.minimum, "Backlight Off register")
            }
        }

        runTest("7. Live Hardware Manual White Balance (Kelvin) & Manual Exposure Time (Shutter) Control") {
            let suiteName = "com.webcamcontroller.livekelvin.\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: suiteName)!
            defer { testDefaults.removePersistentDomain(forName: suiteName) }

            let manager = CameraManager(defaults: testDefaults, enableHotplugWatcher: false)
            defer { manager.shutdown() }

            guard let camera = manager.selectedCamera else {
                throw TestFailure("No USB UVC camera connected")
            }
            let id = camera.identity
            let originalSnapshot = camera.captureSnapshot()
            defer { camera.applySnapshot(originalSnapshot) }

            guard let vh = cuvc_open_device(id.locationId, id.vendorId, id.productId) else {
                throw TestFailure("Failed to open verification handle")
            }
            defer { cuvc_close_device(vh) }

            // Manual White Balance Temperature (3900 K)
            try expect(camera.setWhiteBalanceAuto(false), "Disable Auto White Balance")
            usleep(6_000)
            let targetKelvin = camera.whiteBalanceTemperature.clampedAndSnapped(3900)
            try expect(camera.setWhiteBalanceTemperature(targetKelvin), "Set White Balance 3900K")

            var hwKelvin: Int64 = 0
            _ = cuvc_get_int(vh, UInt8(CUVC_REQ_GET_CUR.rawValue), UInt8(id.processingUnitId), UInt8(CUVC_PU_WHITE_BALANCE_TEMPERATURE_CONTROL.rawValue), 2, false, &hwKelvin)
            try expectEqual(Int(hwKelvin), targetKelvin, "Physical ISP Kelvin register")

            // Manual Exposure Mode + Physical Shutter Exposure Time (200 = 20.0ms = 1/50s)
            if camera.autoExposureMode.isModeSupported(.manual) {
                try expect(camera.setAutoExposureMode(.manual), "Switch AE Mode to Manual")
                usleep(6_000)
                let targetExp = camera.exposureTime.clampedAndSnapped(200)
                try expect(camera.setExposureTime(targetExp), "Set Exposure Time 200")

                var hwExp: Int64 = 0
                _ = cuvc_get_int(vh, UInt8(CUVC_REQ_GET_CUR.rawValue), UInt8(id.cameraTerminalId), UInt8(CUVC_CT_EXPOSURE_TIME_ABSOLUTE_CONTROL.rawValue), 4, false, &hwExp)
                try expectEqual(Int(hwExp), targetExp, "Physical Sensor Exposure Time register")
            }
        }

        runTest("8. Multi-Resolution & FPS Compatibility Matrix Validation (1080p@60fps vs 2K@30fps + YUY2 Clamping)") {
            let syntheticModes: [UVCStreamResolutionMode] = [
                UVCStreamResolutionMode(
                    formatIndex: 1,
                    frameIndex: 1,
                    codec: .mjpeg,
                    width: 1920,
                    height: 1080,
                    defaultFPS: 30,
                    supportedFPS: [15, 24, 30, 60].map { UVCFrameRateOption(fps: $0) }
                ),
                UVCStreamResolutionMode(
                    formatIndex: 1,
                    frameIndex: 2,
                    codec: .mjpeg,
                    width: 2560,
                    height: 1440,
                    defaultFPS: 30,
                    supportedFPS: [15, 24, 30].map { UVCFrameRateOption(fps: $0) }
                ),
                UVCStreamResolutionMode(
                    formatIndex: 2,
                    frameIndex: 1,
                    codec: .uncompressed,
                    width: 2560,
                    height: 1440,
                    defaultFPS: 3,
                    supportedFPS: [UVCFrameRateOption(fps: 3)]
                )
            ]

            let mjpegRes = UVCStreamValidator.resolutions(for: .mjpeg, in: syntheticModes)
            try expectEqual(mjpegRes.first?.width, 2560, "Highest resolution (2K QHD) sorted first")
            try expectEqual(mjpegRes.first?.resolutionStandardBadge, "2K QHD")

            // 1) 60 fps IS valid at 1080p MJPEG
            let sel1080p60 = UVCStreamValidator.validateSelection(
                modes: syntheticModes,
                desiredCodec: .mjpeg,
                desiredWidth: 1920,
                desiredHeight: 1080,
                desiredFPS: 60
            )
            try expectEqual(sel1080p60?.fps, 60, "60 fps unlocked on 1080p")

            // 2) Switching from 1080p@60fps to 2K (max 30fps) MUST clamp FPS to 30fps
            let sel2KFrom60 = UVCStreamValidator.validateSelection(
                modes: syntheticModes,
                desiredCodec: .mjpeg,
                desiredWidth: 2560,
                desiredHeight: 1440,
                desiredFPS: 60
            )
            try expectEqual(sel2KFrom60?.width, 2560)
            try expectEqual(sel2KFrom60?.height, 1440)
            try expectEqual(sel2KFrom60?.fps, 30, "60 fps clamped to max compatible 30 fps on 2K")

            // 3) Switching from MJPEG 2K@30fps to Uncompressed YUY2 2K (only 3fps) MUST clamp to 3fps
            let selYUY2 = UVCStreamValidator.validateSelection(
                modes: syntheticModes,
                desiredCodec: .uncompressed,
                desiredWidth: 2560,
                desiredHeight: 1440,
                desiredFPS: 30
            )
            try expectEqual(selYUY2?.codec, .uncompressed)
            try expectEqual(selYUY2?.fps, 3, "30 fps clamped to 3 fps on Uncompressed 2K")
        }

        runTest("9. Live USB VideoStreaming Descriptor Introspection (2K 2560x1440 @ 30fps) & Stream Rollback") {
            let suiteName = "com.webcamcontroller.livestream.\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: suiteName)!
            defer { testDefaults.removePersistentDomain(forName: suiteName) }

            let manager = CameraManager(defaults: testDefaults, enableHotplugWatcher: false)
            defer { manager.shutdown() }

            guard let camera = manager.selectedCamera else {
                throw TestFailure("No USB UVC camera connected")
            }
            let originalSnapshot = camera.captureSnapshot()
            defer { camera.applySnapshot(originalSnapshot) }

            try expect(!camera.streamModes.isEmpty, "Expected non-empty UVC VideoStreaming modes")
            try expect(camera.defaultStream != nil, "Expected valid hardware default stream")

            // Verify 2K (2560x1440) @ max 30 fps on Creative Live! Cam Sync V3
            if camera.identity.vendorId == 0x041e && camera.identity.productId == 0x40a3 {
                let mjpegModes = UVCStreamValidator.resolutions(for: .mjpeg, in: camera.streamModes)
                let mode2K = mjpegModes.first(where: { $0.width == 2560 && $0.height == 1440 })
                try expect(mode2K != nil, "2560x1440 (2K QHD) MJPEG mode discovered from USB descriptor")
                try expectEqual(mode2K?.maxFPS, 30, "Creative Live! Cam Sync V3 2K max FPS is 30")
                try expect(!(mode2K?.supports(fps: 60) ?? true), "60 fps is not marked compatible on 2K")

                let yuy2Modes = UVCStreamValidator.resolutions(for: .uncompressed, in: camera.streamModes)
                let yuy2_2K = yuy2Modes.first(where: { $0.width == 2560 && $0.height == 1440 })
                try expectEqual(yuy2_2K?.maxFPS, 3, "Uncompressed YUY2 2K max FPS is 3")
            }

            // Negotiate 15 fps on current resolution, verify modification state, then punctual rollback to defaultStream
            if let curMode = camera.currentStreamMode, curMode.supports(fps: 15), camera.defaultStream?.fps != 15 {
                try expect(camera.selectStreamFPS(15), "Negotiate 15 fps over Endpoint 0")
                try expectEqual(camera.selectedStream?.fps, 15, "Selected stream updated to 15 fps")
                try expect(camera.isStreamModifiedFromDefault, "Stream marked modified from default")

                try expect(camera.resetStreamToDefault(), "Rollback stream to hardware default")
                try expectEqual(camera.selectedStream, camera.defaultStream, "Stream rolled back to exact default")
                try expect(!camera.isStreamModifiedFromDefault, "Stream no longer marked modified")
            }
        }

        runTest("10. Punctual Single-Setting Hardware Rollback to Factory Default (GET_DEF)") {
            let suiteName = "com.webcamcontroller.liverollback.\(UUID().uuidString)"
            let testDefaults = UserDefaults(suiteName: suiteName)!
            defer { testDefaults.removePersistentDomain(forName: suiteName) }

            let manager = CameraManager(defaults: testDefaults, enableHotplugWatcher: false)
            defer { manager.shutdown() }

            guard let camera = manager.selectedCamera else {
                throw TestFailure("No USB UVC camera connected")
            }
            let originalSnapshot = camera.captureSnapshot()
            defer { camera.applySnapshot(originalSnapshot) }

            let customBrightness = camera.brightness.defaultValue + 12 <= camera.brightness.maximum
                ? camera.brightness.defaultValue + 12
                : camera.brightness.defaultValue - 12
            let customContrast = camera.contrast.defaultValue + 8 <= camera.contrast.maximum
                ? camera.contrast.defaultValue + 8
                : camera.contrast.defaultValue - 8

            try expect(camera.setBrightness(customBrightness), "Set custom brightness")
            try expect(camera.setContrast(customContrast), "Set custom contrast")

            // Punctually rollback ONLY brightness to GET_DEF while keeping contrast customized
            try expect(camera.setBrightness(camera.brightness.defaultValue), "Rollback brightness to GET_DEF")
            try expectEqual(camera.brightness.current, camera.brightness.defaultValue, "Brightness rolled back to factory default")
            try expectEqual(camera.contrast.current, customContrast, "Contrast remained untouched by punctual brightness rollback")
        }

        print("---------------------------------------------------------------")
        print(" Summary: \(passed) passed, \(failed) failed")
        print("===============================================================")
        if failed > 0 {
            exit(1)
        }
    }
}
