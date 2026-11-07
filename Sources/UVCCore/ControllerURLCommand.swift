import Foundation

/// A command carried by a `webcamcontroller://` URL (Shortcuts "Open URL", Raycast, Stream Deck, `open -g`).
///
///     webcamcontroller://preset/Meeting          apply a saved preset by name, 1-based number, or `default`
///     webcamcontroller://reset                   restore the camera's factory defaults (GET_DEF)
///     webcamcontroller://lock/on | lock/off      Anti-Reset Hardware Lock
///     webcamcontroller://config/on | off | toggle   turn your saved configuration on or off
///     webcamcontroller://camera/Brio             select a camera by index, ID, serial or name
///     webcamcontroller://set?brightness=+8&shutter=1/60   write one or more controls (same tokens as `webcamctl set`)
///
/// Add `?camera=Name` to any link to pick the camera first.
public enum ControllerURLCommand: Equatable, Sendable {
    public enum ConfigurationAction: String, Equatable, Sendable {
        case on, off, toggle
    }

    public struct Assignment: Equatable, Sendable {
        public let control: String
        public let value: String

        public init(control: String, value: String) {
            self.control = control
            self.value = value
        }
    }

    case preset(String)
    case reset
    case resetView
    case resetImage
    case lock(Bool)
    case configuration(ConfigurationAction)
    case camera(String)
    case look(String)
    case set([Assignment])

    public static let scheme = "webcamcontroller"

    /// Returns the command plus the optional `?camera=` selector, or `nil` for anything unrecognized.
    public static func parse(_ url: URL) -> (command: ControllerURLCommand, camera: String?)? {
        guard url.scheme?.lowercased() == scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = comps.host?.lowercased(), !host.isEmpty else {
            return nil
        }

        // Split the still-encoded path first so an encoded "%2F" stays inside a single argument.
        let args = comps.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .compactMap { String($0).removingPercentEncoding }
        let items = comps.queryItems ?? []
        let camera = items.first(where: { $0.name == "camera" })?.value.flatMap { $0.isEmpty ? nil : $0 }

        func isBlank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }

        let command: ControllerURLCommand
        switch (host, args.count) {
        case ("preset", 1) where !isBlank(args[0]):
            command = .preset(args[0])
        case ("reset", 0):
            command = .reset
        case ("reset-view", 0), ("reset_view", 0):
            command = .resetView
        case ("reset-image", 0), ("reset_image", 0):
            command = .resetImage
        case ("lock", 1) where args[0].lowercased() == "on":
            command = .lock(true)
        case ("lock", 1) where args[0].lowercased() == "off":
            command = .lock(false)
        case ("config", 1), ("configuration", 1):
            guard let action = ConfigurationAction(rawValue: args[0].lowercased()) else { return nil }
            command = .configuration(action)
        case ("camera", 1) where !isBlank(args[0]):
            command = .camera(args[0])
        case ("look", 1) where !isBlank(args[0]):
            command = .look(args[0])
        case ("set", 0):
            let assignments = items
                .filter { $0.name != "camera" && !($0.value ?? "").isEmpty }
                .map { Assignment(control: $0.name, value: $0.value ?? "") }
            guard !assignments.isEmpty else { return nil }
            command = .set(assignments)
        default:
            return nil
        }
        return (command, camera)
    }
}
