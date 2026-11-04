import AppKit
import AVFoundation
import CoreAudio
import CoreMediaIO
import Darwin
import Foundation

public struct ActiveCameraClientApp: Equatable, Sendable {
    public enum Evidence: String, Codable, Sendable {
        case microphoneInput = "microphone"
        case frontmostCameraApp = "frontmost"
    }

    public let name: String
    public let bundleID: String?
    public let evidence: Evidence

    public init(name: String, bundleID: String?, evidence: Evidence) {
        self.name = name
        self.bundleID = bundleID
        self.evidence = evidence
    }
}

public struct CameraStreamActivity: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool
    public let isUVC: Bool
    public let uvcRuntimeID: String?
    public let isStreamingSomewhere: Bool

    public init(
        id: String,
        name: String,
        isBuiltIn: Bool,
        isUVC: Bool,
        uvcRuntimeID: String?,
        isStreamingSomewhere: Bool
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isUVC = isUVC
        self.uvcRuntimeID = uvcRuntimeID
        self.isStreamingSomewhere = isStreamingSomewhere
    }
}

public struct CameraCallSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var appNames: String
    public var cameraName: String
    public var startedAt: Date
    public var durationSeconds: Int
    public var streamSummary: String
    public var autoUpgradedFromSlowMode: String?

    public init(
        id: UUID = UUID(),
        appNames: String,
        cameraName: String,
        startedAt: Date,
        durationSeconds: Int,
        streamSummary: String,
        autoUpgradedFromSlowMode: String? = nil
    ) {
        self.id = id
        self.appNames = appNames
        self.cameraName = cameraName
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.streamSummary = streamSummary
        self.autoUpgradedFromSlowMode = autoUpgradedFromSlowMode
    }

    public var formattedDuration: String {
        let s = max(0, durationSeconds)
        if s >= 3600 {
            return String(format: "%dh %02dm", s / 3600, (s / 60) % 60)
        }
        if s >= 60 {
            return String(format: "%dm %02ds", s / 60, s % 60)
        }
        return "\(s)s"
    }
}

/// Passive, zero-permission camera activity detector using CoreMediaIO & CoreAudio process objects.
/// Never opens a video stream, never touches microphone audio, and never triggers macOS TCC prompts.
public enum CameraActivityMonitor {
    private static let knownVideoApps: Set<String> = [
        "com.apple.FaceTime",
        "com.apple.PhotoBooth",
        "com.apple.QuickTimePlayerX",
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "net.whatsapp.WhatsApp",
        "WhatsApp",
        "desktop.WhatsApp",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.obsproject.obs-studio",
        "com.cisco.webexmeetingsapp",
        "com.loom.desktop",
        "ru.keepcoder.Telegram"
    ]

    public static func allCameraActivities(matchingUVCIdentities uvcIdentities: [CameraIdentity] = []) -> [CameraStreamActivity] {
        let avDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices

        var matchedAVUniqueIDs = Set<String>()
        var results: [CameraStreamActivity] = []

        for ident in uvcIdentities {
            let modelToken = "VendorID_\(ident.vendorId) ProductID_\(ident.productId)"
            let locHex = String(format: "%x", ident.locationId).lowercased()
            let matched = avDevices.first {
                $0.modelID.contains(modelToken) && $0.uniqueID.lowercased().contains(locHex)
            } ?? avDevices.first {
                $0.modelID.contains(modelToken)
            }

            let uid = matched?.uniqueID ?? "usb:\(ident.runtimeID)"
            if let m = matched { matchedAVUniqueIDs.insert(m.uniqueID) }
            let streaming = matched != nil ? isCMIODeviceRunningSomewhere(uid: uid) : false
            results.append(
                CameraStreamActivity(
                    id: uid,
                    name: ident.productName,
                    isBuiltIn: false,
                    isUVC: true,
                    uvcRuntimeID: ident.runtimeID,
                    isStreamingSomewhere: streaming
                )
            )
        }

        for dev in avDevices where !matchedAVUniqueIDs.contains(dev.uniqueID) {
            let builtIn = dev.deviceType == .builtInWideAngleCamera
            let streaming = isCMIODeviceRunningSomewhere(uid: dev.uniqueID)
            results.append(
                CameraStreamActivity(
                    id: dev.uniqueID,
                    name: dev.localizedName,
                    isBuiltIn: builtIn,
                    isUVC: false,
                    uvcRuntimeID: nil,
                    isStreamingSomewhere: streaming
                )
            )
        }

        return results
    }

    public static func isUVCCameraStreamingInCoreMediaIO(identity: CameraIdentity) -> Bool {
        let activities = allCameraActivities(matchingUVCIdentities: [identity])
        return activities.first?.isStreamingSomewhere ?? false
    }

    public static func likelyCameraUsers(excluding excludedPID: pid_t = getpid()) -> [ActiveCameraClientApp] {
        let audioApps = audioInputCapturingApps(excluding: excludedPID)
        if !audioApps.isEmpty {
            return audioApps
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != excludedPID,
              let bundleID = front.bundleIdentifier,
              knownVideoApps.contains(bundleID) else {
            return []
        }
        return [
            ActiveCameraClientApp(
                name: front.localizedName ?? bundleID,
                bundleID: bundleID,
                evidence: .frontmostCameraApp
            )
        ]
    }

    public static func audioInputCapturingApps(excluding excludedPID: pid_t = getpid()) -> [ActiveCameraClientApp] {
        var seen = Set<String>()
        var result: [ActiveCameraClientApp] = []

        for obj in coreAudioProcessObjects() {
            guard readCoreAudioProperty(obj, selector: kAudioProcessPropertyIsRunningInput, initial: UInt32(0)) == 1,
                  let pid = readCoreAudioProperty(obj, selector: kAudioProcessPropertyPID, initial: pid_t(0)),
                  pid != excludedPID,
                  let app = resolveOwningApp(forPID: pid) else {
                continue
            }
            let dedupKey = app.bundleID ?? app.name
            if seen.insert(dedupKey).inserted {
                result.append(app)
            }
        }
        return result
    }

    // MARK: - CoreMediaIO Inspection

    private static func isCMIODeviceRunningSomewhere(uid: String) -> Bool {
        guard let obj = findCMIODevice(uid: uid) else { return false }
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var running: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(obj, &address, 0, nil, 4, &used, &running)
        return status == 0 && running != 0
    }

    private static func findCMIODevice(uid: String) -> CMIOObjectID? {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else {
            return nil
        }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &size, &devices) == 0 else {
            return nil
        }
        for dev in devices {
            var uidAddr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var cfValue: Unmanaged<CFString>?
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                dev,
                &uidAddr,
                0,
                nil,
                UInt32(MemoryLayout<Unmanaged<CFString>?>.size),
                &used,
                &cfValue
            )
            if status == 0, let str = cfValue?.takeRetainedValue() as String?, str == uid {
                return dev
            }
        }
        return nil
    }

    // MARK: - CoreAudio Process Inspection

    private static func coreAudioProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else {
            return []
        }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == 0 else {
            return []
        }
        return objects
    }

    private static func readCoreAudioProperty<T: BitwiseCopyable>(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        initial: T
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) { buf in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, buf.baseAddress!)
        }
        return status == 0 ? value : nil
    }

    private static func resolveOwningApp(forPID pid: pid_t) -> ActiveCameraClientApp? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let byteLen = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard byteLen > 0 else { return nil }
        let fullPath = String(decoding: buffer.prefix(Int(byteLen)), as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        let execName = (fullPath as NSString).lastPathComponent

        if execName == "avconferenced" {
            return ActiveCameraClientApp(name: "FaceTime", bundleID: "com.apple.FaceTime", evidence: .microphoneInput)
        }

        let appBundlePath: String? = {
            if let range = fullPath.range(of: ".app/") {
                return String(fullPath[..<range.lowerBound]) + ".app"
            }
            if fullPath.hasSuffix(".app") {
                return fullPath
            }
            return nil
        }()

        guard let appPath = appBundlePath, let bundle = Bundle(path: appPath) else { return nil }
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return ActiveCameraClientApp(
            name: displayName,
            bundleID: bundle.bundleIdentifier,
            evidence: .microphoneInput
        )
    }
}
