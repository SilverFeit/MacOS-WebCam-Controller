import Foundation
import CUVCHardware

public enum AutoExposureMode: Int, CaseIterable, Codable, Sendable, Identifiable {
    case manual = 1
    case auto = 2
    case shutterPriority = 4
    case aperturePriority = 8

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .manual: return "Manual"
        case .auto: return "Auto"
        case .shutterPriority: return "Shutter Priority"
        case .aperturePriority: return "Aperture Priority"
        }
    }

    public var shortTitle: String {
        switch self {
        case .manual: return "Manual"
        case .auto: return "Auto"
        case .shutterPriority: return "Shutter"
        case .aperturePriority: return "Aperture"
        }
    }

    public var allowsManualExposureTime: Bool {
        self == .manual || self == .shutterPriority
    }

    public var allowsManualIris: Bool {
        self == .manual || self == .aperturePriority
    }

    public static func supportedModes(fromBitmask bitmask: Int) -> [AutoExposureMode] {
        if bitmask <= 0 {
            return AutoExposureMode.allCases
        }
        let filtered = AutoExposureMode.allCases.filter { (bitmask & $0.rawValue) != 0 }
        return filtered.isEmpty ? AutoExposureMode.allCases : filtered
    }
}

public enum PowerLineFrequency: Int, CaseIterable, Codable, Sendable, Identifiable {
    case disabled = 0
    case hz50 = 1
    case hz60 = 2
    case auto = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .disabled: return "Disabled"
        case .hz50: return "50 Hz"
        case .hz60: return "60 Hz"
        case .auto: return "Auto"
        }
    }
}

public struct NumericRangeControlState: Equatable, Sendable {
    public var isSupported: Bool
    public var canSet: Bool
    public var minimum: Int
    public var maximum: Int
    public var step: Int
    public var defaultValue: Int
    public var current: Int

    public init(
        isSupported: Bool = false,
        canSet: Bool = false,
        minimum: Int = 0,
        maximum: Int = 100,
        step: Int = 1,
        defaultValue: Int = 0,
        current: Int = 0
    ) {
        self.isSupported = isSupported
        self.canSet = canSet
        self.minimum = minimum
        self.maximum = maximum
        self.step = max(1, step)
        self.defaultValue = defaultValue
        self.current = current
    }

    public func clampedAndSnapped(_ rawValue: Int) -> Int {
        guard maximum > minimum else { return minimum }
        let clamped = min(max(rawValue, minimum), maximum)
        let validStep = max(1, step)
        if validStep == 1 {
            return clamped
        }
        let offset = clamped - minimum
        let steps = Int((Double(offset) / Double(validStep)).rounded())
        let snapped = minimum + (steps * validStep)
        return min(max(snapped, minimum), maximum)
    }

    /// Formats UVC absolute exposure time (100 µs units) into ms and approximate shutter fraction
    public var formattedExposureTime: String {
        guard current > 0 else { return "\(current)" }
        let milliseconds = Double(current) * 0.1
        let seconds = Double(current) * 0.0001
        if seconds >= 0.25 {
            return String(format: "%d (%.2fs)", current, seconds)
        } else {
            let denom = max(1, Int((1.0 / seconds).rounded()))
            return String(format: "%d (~1/%ds · %.1fms)", current, denom, milliseconds)
        }
    }

    public var formattedKelvin: String {
        "\(current) K"
    }

    public var formattedGamma: String {
        String(format: "%d (%.2f)", current, Double(current) / 100.0)
    }

    public var formattedArcsecondsDegrees: String {
        let deg = Double(current) / 3600.0
        return String(format: "%+.1f°", deg)
    }

    public var formattedShutterShort: String {
        UVCValueFormatter.shutterShortLabel(units100us: current)
    }

    public var formattedZoomShort: String {
        UVCValueFormatter.zoomShortLabel(current, minimum: minimum)
    }
}

public enum UVCValueFormatter {
    /// Formats UVC absolute exposure time (`100 µs` units) as photographic shutter speed (`1/60s`, `0.5s`).
    public static func shutterShortLabel(units100us: Int) -> String {
        guard units100us > 0 else { return "0s" }
        let seconds = Double(units100us) / 10_000.0
        if seconds >= 0.4 {
            return String(format: "%.1fs", seconds)
        }
        let denom = max(1, Int((1.0 / seconds).rounded()))
        return "1/\(denom)s"
    }

    /// Parses shutter input like `"1/60"`, `"1/60s"`, `"16.6ms"`, `"0.016s"`, or raw UVC `100 µs` integer `"166"`.
    public static func parseShutterUnits(_ rawInput: String) -> Int? {
        let s = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if let direct = Int(s) {
            return direct
        }
        let withoutS = s.hasSuffix("s") && !s.hasSuffix("ms") ? String(s.dropLast()) : s
        if withoutS.contains("/") {
            let parts = withoutS.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), num > 0, den > 0 {
                let sec = num / den
                return max(1, Int((sec * 10_000.0).rounded()))
            }
        }
        if s.hasSuffix("ms"), let ms = Double(s.dropLast(2)), ms > 0 {
            return max(1, Int((ms * 10.0).rounded()))
        }
        if s.hasSuffix("s"), let sec = Double(withoutS), sec > 0 {
            return max(1, Int((sec * 10_000.0).rounded()))
        }
        return nil
    }

    public static func zoomShortLabel(_ value: Int, minimum: Int) -> String {
        if minimum == 100 && value >= 100 {
            return String(format: "%.1f×", Double(value) / 100.0)
        }
        return "\(value)"
    }
}

public struct UVCExtensionUnit: Equatable, Hashable, Sendable, Codable, Identifiable {
    public var id: UInt8 { unitId }
    public let unitId: UInt8
    public let controlCount: UInt8
    public let guidString: String
    public let controlsBitmap: UInt64

    public init(unitId: UInt8, controlCount: UInt8, guidString: String, controlsBitmap: UInt64) {
        self.unitId = unitId
        self.controlCount = controlCount
        self.guidString = guidString
        self.controlsBitmap = controlsBitmap
    }

    public init(cUnit: CUVCExtensionUnitInfo) {
        let g = cUnit.guidBytes
        let bytes: [UInt8] = [
            g.0, g.1, g.2, g.3, g.4, g.5, g.6, g.7,
            g.8, g.9, g.10, g.11, g.12, g.13, g.14, g.15
        ]
        // USB UVC GUID stores first 3 fields little-endian
        let ordered: [UInt8] = [
            bytes[3], bytes[2], bytes[1], bytes[0],
            bytes[5], bytes[4],
            bytes[7], bytes[6],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ]
        let uuid = UUID(uuid: (
            ordered[0], ordered[1], ordered[2], ordered[3],
            ordered[4], ordered[5], ordered[6], ordered[7],
            ordered[8], ordered[9], ordered[10], ordered[11],
            ordered[12], ordered[13], ordered[14], ordered[15]
        ))
        self.unitId = cUnit.unitId
        self.controlCount = cUnit.controlCount
        self.guidString = uuid.uuidString
        self.controlsBitmap = cUnit.controlsBitmap
    }

    public var knownVendorTitle: String? {
        switch guidString.uppercased() {
        case "69678EE4-410F-40DB-A850-7420D7D8240E":
            return "Vendor Device Information XU"
        case "49E40215-F434-47FE-B158-0E885023E51B":
            return "Vendor Video Pipe XU"
        case "FFE52D21-8030-4E2C-82D9-F587D00540BD":
            return "Vendor Peripheral Control XU"
        case "63610682-5070-49AB-B8CC-B3855E8D221D":
            return "Vendor Video Extension XU"
        case "63610682-5070-49AB-B8CC-B3855E8D2256":
            return "Vendor Hardware Control XU"
        default:
            return nil
        }
    }
}

public struct BooleanControlState: Equatable, Sendable {
    public var isSupported: Bool
    public var canSet: Bool
    public var defaultValue: Bool
    public var current: Bool

    public init(
        isSupported: Bool = false,
        canSet: Bool = false,
        defaultValue: Bool = false,
        current: Bool = false
    ) {
        self.isSupported = isSupported
        self.canSet = canSet
        self.defaultValue = defaultValue
        self.current = current
    }
}

public struct AutoExposureModeState: Equatable, Sendable {
    public var isSupported: Bool
    public var canSet: Bool
    public var supportedBitmask: Int
    public var defaultMode: AutoExposureMode
    public var current: AutoExposureMode

    public init(
        isSupported: Bool = false,
        canSet: Bool = false,
        supportedBitmask: Int = 0,
        defaultMode: AutoExposureMode = .aperturePriority,
        current: AutoExposureMode = .aperturePriority
    ) {
        self.isSupported = isSupported
        self.canSet = canSet
        self.supportedBitmask = supportedBitmask
        self.defaultMode = defaultMode
        self.current = current
    }

    public func isModeSupported(_ mode: AutoExposureMode) -> Bool {
        guard isSupported else { return false }
        if supportedBitmask <= 0 { return true }
        return (supportedBitmask & mode.rawValue) != 0
    }

    public var allowsManualExposureTime: Bool {
        !isSupported || current.allowsManualExposureTime
    }

    public var allowsManualIris: Bool {
        !isSupported || current.allowsManualIris
    }
}

public struct CameraIdentity: Equatable, Hashable, Sendable, Codable {
    public let vendorId: UInt16
    public let productId: UInt16
    public let locationId: UInt32
    public let firmwareBCD: UInt16
    public let uvcVersionBCD: UInt16
    public let videoControlInterfaceNumber: UInt8
    public let cameraTerminalId: Int16
    public let processingUnitId: Int16
    public let extensionUnits: [UVCExtensionUnit]
    public let productName: String
    public let vendorName: String
    public let serialNumber: String
    /// `bcdUSB` advertised by the device (`0x0200` = USB 2.0, `0x0300` = USB 3.0). `0` when unknown.
    public let usbSpecBCD: UInt16
    /// IOKit `USBDeviceSpeed`: 0 low, 1 full, 2 high, 3 SuperSpeed, 4 SuperSpeed+. `0` when unknown.
    public let usbSpeed: UInt8

    public init(
        vendorId: UInt16,
        productId: UInt16,
        locationId: UInt32,
        firmwareBCD: UInt16 = 0,
        uvcVersionBCD: UInt16,
        videoControlInterfaceNumber: UInt8,
        cameraTerminalId: Int16,
        processingUnitId: Int16,
        extensionUnits: [UVCExtensionUnit] = [],
        productName: String,
        vendorName: String,
        serialNumber: String,
        usbSpecBCD: UInt16 = 0,
        usbSpeed: UInt8 = 0
    ) {
        self.usbSpecBCD = usbSpecBCD
        self.usbSpeed = usbSpeed
        self.vendorId = vendorId
        self.productId = productId
        self.locationId = locationId
        self.firmwareBCD = firmwareBCD
        self.uvcVersionBCD = uvcVersionBCD
        self.videoControlInterfaceNumber = videoControlInterfaceNumber
        self.cameraTerminalId = cameraTerminalId
        self.processingUnitId = processingUnitId
        self.extensionUnits = extensionUnits
        self.productName = productName
        self.vendorName = vendorName
        self.serialNumber = serialNumber
    }

    public init(cInfo: CUVCDeviceInfo) {
        let prod = withUnsafePointer(to: cInfo.productName) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let vend = withUnsafePointer(to: cInfo.vendorName) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) {
                String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let serial = withUnsafePointer(to: cInfo.serialNumber) {
            $0.withMemoryRebound(to: CChar.self, capacity: 128) {
                String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let xuCount = min(Int(cInfo.extensionUnitCount), Int(CUVC_MAX_EXTENSION_UNITS))
        let allRawXUs: [CUVCExtensionUnitInfo] = [
            cInfo.extensionUnits.0, cInfo.extensionUnits.1,
            cInfo.extensionUnits.2, cInfo.extensionUnits.3,
            cInfo.extensionUnits.4, cInfo.extensionUnits.5,
            cInfo.extensionUnits.6, cInfo.extensionUnits.7
        ]
        let parsedXUs = allRawXUs.prefix(xuCount).map { UVCExtensionUnit(cUnit: $0) }

        self.vendorId = cInfo.vendorId
        self.productId = cInfo.productId
        self.locationId = cInfo.locationId
        self.firmwareBCD = cInfo.firmwareBCD
        self.uvcVersionBCD = cInfo.uvcVersionBCD
        self.videoControlInterfaceNumber = cInfo.videoControlInterfaceNumber
        self.cameraTerminalId = cInfo.cameraTerminalId
        self.processingUnitId = cInfo.processingUnitId
        self.extensionUnits = parsedXUs
        self.productName = prod.isEmpty ? String(format: "USB Camera (0x%04x:0x%04x)", cInfo.vendorId, cInfo.productId) : prod
        self.vendorName = vend
        self.serialNumber = serial
        self.usbSpecBCD = cInfo.usbSpecBCD
        self.usbSpeed = cInfo.usbSpeed
    }

    /// Human-readable negotiated USB link speed (`USB 2.0 High-Speed`, `USB 3 SuperSpeed`...).
    public var usbSpeedTitle: String {
        switch usbSpeed {
        case 1: return "USB Full-Speed (12 Mb/s)"
        case 2: return "USB 2.0 High-Speed (480 Mb/s)"
        case 3: return "USB 3 SuperSpeed (5 Gb/s)"
        case 4: return "USB 3 SuperSpeed+ (10 Gb/s)"
        case 0 where usbSpecBCD == 0: return "unknown"
        case 0: return "USB 1.0 Low-Speed"
        default: return "USB speed \(usbSpeed)"
        }
    }

    /// Set when a USB 3 camera (advertises `bcdUSB >= 3.0`) enumerated below SuperSpeed, which usually means a
    /// USB 2 port, hub or cable is capping resolution / frame rate.
    public var usbLinkWarning: String? {
        Self.usbLinkWarning(bcdUSB: Int(usbSpecBCD), speed: Int(usbSpeed))
    }

    public static func usbLinkWarning(bcdUSB: Int, speed: Int) -> String? {
        guard bcdUSB >= 0x0300, speed > 0, speed < 3 else { return nil }
        return "Connected at USB 2 speed. Use a USB 3 port or cable for full resolution and frame rate."
    }

    public var firmwareHex: String {
        String(format: "0x%04x", firmwareBCD)
    }

    /// Hardware model key `vvvv:pppp` (matches across USB ports)
    public var modelKey: String {
        String(format: "%04x:%04x", vendorId, productId)
    }

    /// Unique runtime instance ID on the USB bus
    public var runtimeID: String {
        String(format: "%04x:%04x@%08x", vendorId, productId, locationId)
    }

    /// Persistent hardware ID (`vvvv:pppp:serial` if serial exists, else `vvvv:pppp@location`)
    public var persistentID: String {
        if !serialNumber.isEmpty {
            return "\(modelKey):\(serialNumber)"
        }
        return runtimeID
    }

    public var vidPidHex: String {
        String(format: "0x%04x:0x%04x", vendorId, productId)
    }

    public var locationHex: String {
        String(format: "0x%08x", locationId)
    }

    public var uvcVersionString: String {
        let major = (uvcVersionBCD >> 8) & 0xFF
        let minor = uvcVersionBCD & 0xFF
        return String(format: "%x.%02x", major, minor)
    }

    public func matchesConfiguredID(_ configuredID: String) -> Bool {
        if configuredID.isEmpty { return false }
        if persistentID.caseInsensitiveCompare(configuredID) == .orderedSame { return true }
        if runtimeID.caseInsensitiveCompare(configuredID) == .orderedSame { return true }
        if modelKey.caseInsensitiveCompare(configuredID) == .orderedSame { return true }
        // Match by prefix `vvvv:pppp` if plugged into a different USB port
        let prefixKey = String(configuredID.prefix(9))
        return modelKey.caseInsensitiveCompare(prefixKey) == .orderedSame
    }
}
