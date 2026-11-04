import Foundation
import OSLog

public enum DiagnosticsLogger {
    private static let logger = Logger(subsystem: "com.webcamcontroller.uvc", category: "hardware")
    private static let queue = DispatchQueue(label: "com.webcamcontroller.uvc.diagnostics")

    public static var logFileURL: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return lib.appendingPathComponent("Logs/WebCamController.log")
    }

    public static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        let url = logFileURL
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? Int, size > 1_000_000 {
                try? fm.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }
    }

    public static func ioReturnDescription(_ code: Int32) -> String {
        let raw = UInt32(bitPattern: code)
        switch raw {
        case 0:
            return "ok"
        case 0xE000_404F:
            return "camera rejected request (USB pipe stalled)"
        case 0xE000_4051:
            return "USB transaction timed out"
        case 0xE000_02C0:
            return "USB camera disconnected"
        case 0xE000_02C5:
            return "interface held exclusively by another process"
        case 0xE000_02C7:
            return "unsupported by camera firmware"
        case 0xE000_02CD:
            return "USB interface not open"
        case 0xE000_02D6:
            return "I/O timed out"
        default:
            return String(format: "IOKit error 0x%08x", raw)
        }
    }
}
