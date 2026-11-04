import Foundation
import CUVCHardware

public enum UVCVideoCodec: Int, CaseIterable, Codable, Sendable, Identifiable {
    case uncompressed = 1
    case mjpeg = 2
    case frameBased = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .mjpeg: return "MJPEG"
        case .uncompressed: return "Uncompressed (YUY2)"
        case .frameBased: return "H.264 / Frame"
        }
    }

    public var shortTitle: String {
        switch self {
        case .mjpeg: return "MJPEG"
        case .uncompressed: return "YUY2"
        case .frameBased: return "H.264"
        }
    }

    /// Preferred ordering so high-FPS compressed modes (MJPEG / H.264) appear first.
    public var priorityOrder: Int {
        switch self {
        case .mjpeg: return 0
        case .frameBased: return 1
        case .uncompressed: return 2
        }
    }
}

public struct UVCFrameRateOption: Equatable, Hashable, Codable, Sendable, Identifiable {
    public let fps: Int
    public let interval100ns: UInt32

    public var id: Int { fps }

    public init(fps: Int, interval100ns: UInt32? = nil) {
        let safeFPS = max(1, fps)
        self.fps = safeFPS
        self.interval100ns = interval100ns ?? UInt32(10_000_000 / safeFPS)
    }

    public static func fpsFromInterval(_ interval100ns: UInt32) -> Int {
        guard interval100ns > 0 else { return 0 }
        return max(1, Int((10_000_000.0 / Double(interval100ns)).rounded()))
    }
}

public struct UVCStreamResolutionMode: Equatable, Hashable, Codable, Sendable, Identifiable {
    public let vsInterfaceNumber: UInt8
    public let formatIndex: UInt8
    public let frameIndex: UInt8
    public let codec: UVCVideoCodec
    public let width: Int
    public let height: Int
    public let defaultFPS: Int
    public let defaultInterval100ns: UInt32
    /// Sorted ascending by `fps` (e.g. `[5, 10, 15, 20, 25, 30]`)
    public let supportedFPS: [UVCFrameRateOption]

    public var id: String {
        "\(vsInterfaceNumber)-\(codec.rawValue)-\(formatIndex)-\(frameIndex)-\(width)x\(height)"
    }

    public var resolutionKey: String {
        "\(width)x\(height)"
    }

    public var pixelCount: Int {
        width * height
    }

    public var minFPS: Int {
        supportedFPS.first?.fps ?? defaultFPS
    }

    public var maxFPS: Int {
        supportedFPS.last?.fps ?? defaultFPS
    }

    public var resolutionStandardBadge: String? {
        switch (width, height) {
        case (3840, 2160), (4096, 2160): return "4K UHD"
        case (2560, 1440): return "2K QHD"
        case (2592, 1944): return "5MP"
        case (1920, 1080): return "1080p FHD"
        case (1600, 1200): return "UXGA"
        case (1280, 720): return "720p HD"
        case (1024, 768): return "XGA"
        case (960, 540), (960, 544): return "qHD"
        case (800, 600): return "SVGA"
        case (640, 480): return "VGA"
        case (640, 360): return "360p"
        case (320, 240): return "QVGA"
        default: return nil
        }
    }

    public var displayTitle: String {
        if let badge = resolutionStandardBadge {
            return "\(width) × \(height) (\(badge))"
        }
        return "\(width) × \(height)"
    }

    public var pickerTitle: String {
        if minFPS == maxFPS {
            return "\(displayTitle)  ·  \(maxFPS) fps"
        }
        return "\(displayTitle)  ·  max \(maxFPS) fps"
    }

    public init(
        vsInterfaceNumber: UInt8 = 1,
        formatIndex: UInt8,
        frameIndex: UInt8,
        codec: UVCVideoCodec,
        width: Int,
        height: Int,
        defaultFPS: Int,
        defaultInterval100ns: UInt32? = nil,
        supportedFPS: [UVCFrameRateOption]
    ) {
        self.vsInterfaceNumber = vsInterfaceNumber
        self.formatIndex = formatIndex
        self.frameIndex = frameIndex
        self.codec = codec
        self.width = width
        self.height = height
        let sorted = supportedFPS.sorted { $0.fps < $1.fps }
        self.supportedFPS = sorted
        let resolvedDefFPS = sorted.contains(where: { $0.fps == defaultFPS })
            ? defaultFPS
            : (sorted.last?.fps ?? max(1, defaultFPS))
        self.defaultFPS = resolvedDefFPS
        self.defaultInterval100ns = defaultInterval100ns
            ?? sorted.first(where: { $0.fps == resolvedDefFPS })?.interval100ns
            ?? UInt32(10_000_000 / max(1, resolvedDefFPS))
    }

    public init?(cMode: CUVCStreamMode) {
        guard let codec = UVCVideoCodec(rawValue: Int(cMode.codec)),
              cMode.width > 0,
              cMode.height > 0,
              cMode.intervalCount > 0 else {
            return nil
        }

        let count = min(Int(cMode.intervalCount), Int(CUVC_MAX_FPS_INTERVALS))
        let rawIntervals: [UInt32] = withUnsafePointer(to: cMode.frameIntervals100ns) { tuplePtr in
            tuplePtr.withMemoryRebound(to: UInt32.self, capacity: Int(CUVC_MAX_FPS_INTERVALS)) { bufPtr in
                Array(UnsafeBufferPointer(start: bufPtr, count: count))
            }
        }

        var optionsByFPS: [Int: UVCFrameRateOption] = [:]
        for iv in rawIntervals where iv > 0 {
            let fps = UVCFrameRateOption.fpsFromInterval(iv)
            if fps > 0 && optionsByFPS[fps] == nil {
                optionsByFPS[fps] = UVCFrameRateOption(fps: fps, interval100ns: iv)
            }
        }

        let sortedOptions = optionsByFPS.values.sorted { $0.fps < $1.fps }
        guard !sortedOptions.isEmpty else { return nil }

        let defIv = cMode.defaultFrameInterval100ns > 0
            ? cMode.defaultFrameInterval100ns
            : sortedOptions.last!.interval100ns
        let rawDefFPS = UVCFrameRateOption.fpsFromInterval(defIv)
        let matchedDefOption = sortedOptions.min(by: { abs($0.fps - rawDefFPS) < abs($1.fps - rawDefFPS) })!

        self.vsInterfaceNumber = cMode.videoStreamingInterfaceNumber
        self.formatIndex = cMode.formatIndex
        self.frameIndex = cMode.frameIndex
        self.codec = codec
        self.width = Int(cMode.width)
        self.height = Int(cMode.height)
        self.defaultFPS = matchedDefOption.fps
        self.defaultInterval100ns = matchedDefOption.interval100ns
        self.supportedFPS = sortedOptions
    }

    public func supports(fps: Int) -> Bool {
        supportedFPS.contains(where: { $0.fps == fps })
    }

    public func option(forFPS targetFPS: Int) -> UVCFrameRateOption? {
        supportedFPS.first(where: { $0.fps == targetFPS })
    }
}

public struct UVCStreamSelection: Equatable, Hashable, Codable, Sendable {
    public let vsInterfaceNumber: UInt8
    public let codec: UVCVideoCodec
    public let formatIndex: UInt8
    public let frameIndex: UInt8
    public let width: Int
    public let height: Int
    public let fps: Int
    public let interval100ns: UInt32

    public init(
        vsInterfaceNumber: UInt8,
        codec: UVCVideoCodec,
        formatIndex: UInt8,
        frameIndex: UInt8,
        width: Int,
        height: Int,
        fps: Int,
        interval100ns: UInt32
    ) {
        self.vsInterfaceNumber = vsInterfaceNumber
        self.codec = codec
        self.formatIndex = formatIndex
        self.frameIndex = frameIndex
        self.width = width
        self.height = height
        self.fps = fps
        self.interval100ns = interval100ns
    }

    public init(mode: UVCStreamResolutionMode, option: UVCFrameRateOption) {
        self.vsInterfaceNumber = mode.vsInterfaceNumber
        self.codec = mode.codec
        self.formatIndex = mode.formatIndex
        self.frameIndex = mode.frameIndex
        self.width = mode.width
        self.height = mode.height
        self.fps = option.fps
        self.interval100ns = option.interval100ns
    }

    public var resolutionKey: String {
        "\(width)x\(height)"
    }

    public var compactSummary: String {
        "\(width)×\(height) @ \(fps) fps"
    }

    public var detailedSummary: String {
        "\(width)×\(height) @ \(fps) fps (\(codec.shortTitle))"
    }
}

public enum UVCStreamValidator {
    /// Distinct hardware codecs sorted by practical streaming priority (`MJPEG`, `H.264`, `Uncompressed`).
    public static func availableCodecs(in modes: [UVCStreamResolutionMode]) -> [UVCVideoCodec] {
        var seen = Set<UVCVideoCodec>()
        for mode in modes {
            seen.insert(mode.codec)
        }
        return seen.sorted { $0.priorityOrder < $1.priorityOrder }
    }

    /// Resolutions available for `codec`, sorted descending from highest resolution (e.g. 4K / 2K) to lowest.
    public static func resolutions(
        for codec: UVCVideoCodec,
        in modes: [UVCStreamResolutionMode]
    ) -> [UVCStreamResolutionMode] {
        var uniqueByRes: [String: UVCStreamResolutionMode] = [:]
        for mode in modes where mode.codec == codec {
            if let existing = uniqueByRes[mode.resolutionKey] {
                if mode.maxFPS > existing.maxFPS {
                    uniqueByRes[mode.resolutionKey] = mode
                }
            } else {
                uniqueByRes[mode.resolutionKey] = mode
            }
        }
        return uniqueByRes.values.sorted { lhs, rhs in
            if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount > rhs.pixelCount }
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            return lhs.maxFPS > rhs.maxFPS
        }
    }

    /// Union of all FPS tiers across all modes of the camera, sorted ascending (e.g. `[3, 5, 10, 15, 20, 25, 30, 60]`).
    public static func allFPSTiers(in modes: [UVCStreamResolutionMode]) -> [Int] {
        var tiers = Set<Int>()
        for mode in modes {
            for opt in mode.supportedFPS {
                tiers.insert(opt.fps)
            }
        }
        return tiers.sorted()
    }

    /// Union of FPS tiers supported across resolutions of a specific `codec`, sorted ascending.
    public static func fpsTiers(
        for codec: UVCVideoCodec,
        in modes: [UVCStreamResolutionMode]
    ) -> [Int] {
        var tiers = Set<Int>()
        for mode in modes where mode.codec == codec {
            for opt in mode.supportedFPS {
                tiers.insert(opt.fps)
            }
        }
        return tiers.sorted()
    }

    public static func compatibleFPS(for mode: UVCStreamResolutionMode) -> Set<Int> {
        Set(mode.supportedFPS.map(\.fps))
    }

    /// Hardware descriptor factory default stream (`bFrameIndex == 1` of primary codec + `dwDefaultFrameInterval`).
    public static func defaultSelection(in modes: [UVCStreamResolutionMode]) -> UVCStreamSelection? {
        guard let primaryCodec = availableCodecs(in: modes).first else { return nil }
        let codecModes = modes.filter { $0.codec == primaryCodec }
        guard let defMode = codecModes.first(where: { $0.frameIndex == 1 }) ?? codecModes.first else {
            return nil
        }
        let opt = defMode.option(forFPS: defMode.defaultFPS) ?? defMode.supportedFPS.last!
        return UVCStreamSelection(mode: defMode, option: opt)
    }

    /// Maps a live `CUVCActiveStreamState` read from USB `VS_COMMIT_CONTROL` / `VS_PROBE_CONTROL` into a validated selection.
    public static func selectionFromHardwareState(
        _ state: CUVCActiveStreamState,
        in modes: [UVCStreamResolutionMode]
    ) -> UVCStreamSelection? {
        guard state.isValid else { return nil }
        guard let mode = modes.first(where: {
            $0.vsInterfaceNumber == state.videoStreamingInterfaceNumber &&
            $0.formatIndex == state.formatIndex &&
            $0.frameIndex == state.frameIndex
        }) ?? modes.first(where: {
            $0.formatIndex == state.formatIndex &&
            $0.frameIndex == state.frameIndex
        }) else {
            return nil
        }

        let liveFPS = UVCFrameRateOption.fpsFromInterval(state.frameInterval100ns)
        guard let opt = mode.supportedFPS.min(by: { abs($0.fps - liveFPS) < abs($1.fps - liveFPS) }) else {
            return nil
        }
        return UVCStreamSelection(mode: mode, option: opt)
    }

    /// Validates `(desiredCodec, desiredWidth, desiredHeight, desiredFPS)` against hardware capabilities,
    /// clamping incompatible FPS values (e.g. `60 fps` on `1080p` -> `30 fps` when switching to `2K`).
    public static func validateSelection(
        modes: [UVCStreamResolutionMode],
        desiredCodec: UVCVideoCodec,
        desiredWidth: Int,
        desiredHeight: Int,
        desiredFPS: Int
    ) -> UVCStreamSelection? {
        let codecs = availableCodecs(in: modes)
        guard let resolvedCodec = codecs.contains(desiredCodec) ? desiredCodec : codecs.first else {
            return nil
        }

        let resList = resolutions(for: resolvedCodec, in: modes)
        guard !resList.isEmpty else { return nil }

        let targetPixels = desiredWidth * desiredHeight
        let resolvedMode = resList.first(where: {
            $0.width == desiredWidth && $0.height == desiredHeight
        }) ?? resList.min(by: {
            abs($0.pixelCount - targetPixels) < abs($1.pixelCount - targetPixels)
        })!

        guard !resolvedMode.supportedFPS.isEmpty else { return nil }

        let resolvedOption: UVCFrameRateOption
        if let exact = resolvedMode.option(forFPS: desiredFPS) {
            resolvedOption = exact
        } else if let highestNotExceeding = resolvedMode.supportedFPS.filter({ $0.fps <= desiredFPS }).last {
            // E.g. 60 fps requested on 2K (max 30 fps) -> clamps down to 30 fps
            resolvedOption = highestNotExceeding
        } else {
            // E.g. 3 fps requested when switching from YUY2 to MJPEG (min 5 fps) -> clamps up to 5 fps
            resolvedOption = resolvedMode.supportedFPS.first!
        }

        return UVCStreamSelection(mode: resolvedMode, option: resolvedOption)
    }
}
