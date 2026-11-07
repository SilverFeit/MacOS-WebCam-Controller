import Foundation
import CUVCHardware

/// Describes a vendor-specific UVC Extension Unit (XU) control profile for cameras that expose extra capabilities
/// (such as HDR, Field of View 65°/78°/95°, EV bias, Face Focus/Exposure, or AI Mic Noise Reduction) on a vendor XU.
public struct VendorProfile: Codable, Equatable, Sendable {
    public struct ChoiceOption: Codable, Equatable, Sendable, Identifiable {
        public var id: Int { value }
        public let value: Int
        public let label: String

        public init(value: Int, label: String) {
            self.value = value
            self.label = label
        }
    }

    public enum ControlKind: String, Codable, Equatable, Sendable {
        case toggle
        case choice
        case range
    }

    public enum EncodingKind: String, Codable, Equatable, Sendable {
        case u8 = "u8"
        case u16le = "u16le"
        case i16le = "i16le"
        case bitInU16le = "bit-in-u16le"
        case u8AtOffset = "u8-at-offset"
        case u16leAtOffset = "u16le-at-offset"
    }

    public struct ControlSpec: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let unitID: UInt8?
        public let unitGUID: String?
        public let selector: UInt8
        public let kind: ControlKind
        public let encoding: EncodingKind
        public let bit: Int?
        public let offset: Int?
        public let length: Int?
        public let min: Int?
        public let max: Int?
        public let step: Int?
        public let naturalDefault: Int?
        public let options: [ChoiceOption]?
    }

    public struct ForbiddenSelector: Codable, Equatable, Sendable {
        public let unitID: UInt8?
        public let selector: UInt8
        public let reason: String?
    }

    public let name: String
    public let vendorID: UInt16
    public let productIDs: [UInt16]?
    public let controls: [ControlSpec]
    public let forbiddenSelectors: [ForbiddenSelector]?

    public func matches(identity: CameraIdentity) -> Bool {
        guard identity.vendorId == vendorID else { return false }
        if let pids = productIDs, !pids.isEmpty {
            return pids.contains(identity.productId)
        }
        return true
    }
}

/// Live probed state of a single vendor Extension Unit control on an attached camera.
public struct VendorXUControlState: Equatable, Sendable, Identifiable {
    public let spec: VendorProfile.ControlSpec
    public let resolvedUnitID: UInt8
    public var isSupported: Bool
    public var canSet: Bool
    public var minimum: Int
    public var maximum: Int
    public var step: Int
    public var defaultValue: Int
    public var current: Int

    public var id: String { spec.id }
    public var name: String { spec.name }

    public var isModifiedFromDefault: Bool {
        isSupported && current != defaultValue
    }

    public var formattedValue: String {
        switch spec.kind {
        case .toggle:
            return current != 0 ? "On" : "Off"
        case .choice:
            if let match = spec.options?.first(where: { $0.value == current }) {
                return match.label
            }
            return "\(current)"
        case .range:
            return "\(current)"
        }
    }
}

public enum VendorProfileRegistry {
    /// Directory where users can drop custom JSON camera profiles (`~/Library/Application Support/WebCamController/Profiles`).
    public static var userProfilesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("WebCamController", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    public static func matchingProfile(for identity: CameraIdentity) -> VendorProfile? {
        let all = loadUserProfiles() + bundledProfiles
        // Prefer exact productID match first, then vendor-wide fallback
        if let exact = all.first(where: { $0.vendorID == identity.vendorId && ($0.productIDs?.contains(identity.productId) == true) }) {
            return exact
        }
        return all.first(where: { $0.matches(identity: identity) })
    }

    public static func loadUserProfiles() -> [VendorProfile] {
        let dir = userProfilesDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var loaded: [VendorProfile] = []
        let decoder = JSONDecoder()
        for url in urls where url.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: url),
               let profile = try? decoder.decode(VendorProfile.self, from: data) {
                loaded.append(profile)
            }
        }
        return loaded
    }

    // MARK: - Bundled Hardware Profiles (Insta360 Link Series, Anker PowerConf C200, AnkerWork C310)

    public static let bundledProfiles: [VendorProfile] = [
        VendorProfile(
            name: "Insta360 Link Series",
            vendorID: 0x2E1A,
            productIDs: nil,
            controls: [
                VendorProfile.ControlSpec(
                    id: "hdr",
                    name: "HDR Mode",
                    unitID: 9,
                    unitGUID: "e537228c-0c3f-4c2b-9a8d-7d5c62319201",
                    selector: 4,
                    kind: .toggle,
                    encoding: .u8AtOffset,
                    bit: nil,
                    offset: 0,
                    length: 3,
                    min: 0,
                    max: 1,
                    step: 1,
                    naturalDefault: 0,
                    options: nil
                ),
                VendorProfile.ControlSpec(
                    id: "exposure_compensation",
                    name: "Exposure Compensation (EV)",
                    unitID: 9,
                    unitGUID: "e537228c-0c3f-4c2b-9a8d-7d5c62319201",
                    selector: 16,
                    kind: .range,
                    encoding: .i16le,
                    bit: nil,
                    offset: nil,
                    length: nil,
                    min: -30,
                    max: 30,
                    step: 1,
                    naturalDefault: 0,
                    options: nil
                )
            ],
            forbiddenSelectors: [
                VendorProfile.ForbiddenSelector(
                    unitID: 9,
                    selector: 17,
                    reason: "Firmware/USB mode switch that disconnects the camera until power-cycled"
                )
            ]
        ),
        VendorProfile(
            name: "Anker PowerConf C200",
            vendorID: 0x291A,
            productIDs: [0x3369],
            controls: [
                VendorProfile.ControlSpec(
                    id: "fov",
                    name: "Field of View",
                    unitID: 6,
                    unitGUID: nil,
                    selector: 4,
                    kind: .choice,
                    encoding: .u8AtOffset,
                    bit: nil,
                    offset: 1,
                    length: 2,
                    min: 0,
                    max: 2,
                    step: 1,
                    naturalDefault: 2,
                    options: [
                        .init(value: 0, label: "65°"),
                        .init(value: 1, label: "78°"),
                        .init(value: 2, label: "95°")
                    ]
                ),
                VendorProfile.ControlSpec(
                    id: "face_focus",
                    name: "Face Auto-Focus",
                    unitID: 6,
                    unitGUID: nil,
                    selector: 2,
                    kind: .toggle,
                    encoding: .bitInU16le,
                    bit: 6,
                    offset: nil,
                    length: nil,
                    min: 0,
                    max: 1,
                    step: 1,
                    naturalDefault: 1,
                    options: nil
                ),
                VendorProfile.ControlSpec(
                    id: "face_exposure",
                    name: "Face Auto-Exposure",
                    unitID: 6,
                    unitGUID: nil,
                    selector: 2,
                    kind: .toggle,
                    encoding: .bitInU16le,
                    bit: 7,
                    offset: nil,
                    length: nil,
                    min: 0,
                    max: 1,
                    step: 1,
                    naturalDefault: 1,
                    options: nil
                ),
                VendorProfile.ControlSpec(
                    id: "ai_noise_reduction",
                    name: "AI Mic Noise Reduction",
                    unitID: 6,
                    unitGUID: nil,
                    selector: 2,
                    kind: .toggle,
                    encoding: .bitInU16le,
                    bit: 11,
                    offset: nil,
                    length: nil,
                    min: 0,
                    max: 1,
                    step: 1,
                    naturalDefault: 1,
                    options: nil
                )
            ],
            forbiddenSelectors: nil
        ),
        VendorProfile(
            name: "AnkerWork C310",
            vendorID: 0x291A,
            productIDs: [0x3367],
            controls: [
                VendorProfile.ControlSpec(
                    id: "hdr",
                    name: "HDR Mode",
                    unitID: 6,
                    unitGUID: nil,
                    selector: 2,
                    kind: .toggle,
                    encoding: .bitInU16le,
                    bit: 0,
                    offset: nil,
                    length: nil,
                    min: 0,
                    max: 1,
                    step: 1,
                    naturalDefault: 0,
                    options: nil
                ),
                VendorProfile.ControlSpec(
                    id: "fov",
                    name: "Field of View",
                    unitID: 6,
                    unitGUID: nil,
                    selector: 4,
                    kind: .choice,
                    encoding: .u8AtOffset,
                    bit: nil,
                    offset: 1,
                    length: 2,
                    min: 0,
                    max: 2,
                    step: 1,
                    naturalDefault: 2,
                    options: [
                        .init(value: 0, label: "65°"),
                        .init(value: 1, label: "78°"),
                        .init(value: 2, label: "95°")
                    ]
                ),
                VendorProfile.ControlSpec(
                    id: "face_focus",
                    name: "Face Auto-Focus",
                    unitID: 6,
                    unitGUID: nil,
                    selector: 2,
                    kind: .toggle,
                    encoding: .bitInU16le,
                    bit: 6,
                    offset: nil,
                    length: nil,
                    min: 0,
                    max: 1,
                    step: 1,
                    naturalDefault: 1,
                    options: nil
                ),
                VendorProfile.ControlSpec(
                    id: "face_exposure",
                    name: "Face Auto-Exposure",
                    unitID: 6,
                    unitGUID: nil,
                    selector: 2,
                    kind: .toggle,
                    encoding: .bitInU16le,
                    bit: 7,
                    offset: nil,
                    length: nil,
                    min: 0,
                    max: 1,
                    step: 1,
                    naturalDefault: 1,
                    options: nil
                )
            ],
            forbiddenSelectors: nil
        )
    ]
}
