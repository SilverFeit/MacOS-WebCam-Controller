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
    public let uvcVersionBCD: UInt16
    public let videoControlInterfaceNumber: UInt8
    public let cameraTerminalId: Int16
    public let processingUnitId: Int16
    public let productName: String
    public let vendorName: String
    public let serialNumber: String

    public init(
        vendorId: UInt16,
        productId: UInt16,
        locationId: UInt32,
        uvcVersionBCD: UInt16,
        videoControlInterfaceNumber: UInt8,
        cameraTerminalId: Int16,
        processingUnitId: Int16,
        productName: String,
        vendorName: String,
        serialNumber: String
    ) {
        self.vendorId = vendorId
        self.productId = productId
        self.locationId = locationId
        self.uvcVersionBCD = uvcVersionBCD
        self.videoControlInterfaceNumber = videoControlInterfaceNumber
        self.cameraTerminalId = cameraTerminalId
        self.processingUnitId = processingUnitId
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

        self.vendorId = cInfo.vendorId
        self.productId = cInfo.productId
        self.locationId = cInfo.locationId
        self.uvcVersionBCD = cInfo.uvcVersionBCD
        self.videoControlInterfaceNumber = cInfo.videoControlInterfaceNumber
        self.cameraTerminalId = cInfo.cameraTerminalId
        self.processingUnitId = cInfo.processingUnitId
        self.productName = prod.isEmpty ? String(format: "USB Camera (0x%04x:0x%04x)", cInfo.vendorId, cInfo.productId) : prod
        self.vendorName = vend
        self.serialNumber = serial
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
