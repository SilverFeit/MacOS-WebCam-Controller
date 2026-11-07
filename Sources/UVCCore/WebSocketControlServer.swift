import Foundation
import Network
import Darwin

/// Embedded WebSocket server (`ws://`) that lets local tools, browsers, Stream Deck, TouchOSC, Home Assistant,
/// or other computers/phones on the LAN inspect and control USB UVC cameras in real time over the network.
@MainActor
public final class WebSocketControlServer: ObservableObject {
    public static let defaultPort: Int = 8765

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var activePort: Int = WebSocketControlServer.defaultPort
    @Published public private(set) var connectedClientsCount: Int = 0
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var lastCommandSummary: String = ""

    private weak var manager: CameraManager?
    private var listener: NWListener?
    private let networkQueue = DispatchQueue(label: "com.webcamcontroller.websocket.server", qos: .userInitiated)

    private final class ClientSession {
        let id: UUID = UUID()
        let connection: NWConnection
        var isAuthenticated: Bool

        init(connection: NWConnection, isAuthenticated: Bool) {
            self.connection = connection
            self.isAuthenticated = isAuthenticated
        }
    }

    private var sessions: [UUID: ClientSession] = [:]

    public init(manager: CameraManager? = nil) {
        self.manager = manager
    }

    public func attach(manager: CameraManager) {
        self.manager = manager
    }

    // MARK: - Endpoint URLs & LAN IP Discovery

    public var localhostURLString: String {
        "ws://127.0.0.1:\(activePort)"
    }

    public var lanURLString: String? {
        guard let ip = Self.primaryLANIPv4Address() else { return nil }
        return "ws://\(ip):\(activePort)"
    }

    public func displayEndpointURL(allowLAN: Bool) -> String {
        if allowLAN, let lan = lanURLString {
            return lan
        }
        return localhostURLString
    }

    /// Returns the primary non-loopback IPv4 LAN address (e.g. `192.168.1.42` on `en0`/`en1`), if available.
    public nonisolated static func primaryLANIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferredCandidate: String?
        var fallbackCandidate: String?

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, !isLoopback, let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ip = hostname.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                    if !ip.hasPrefix("169.254.") && !ip.hasPrefix("127.") {
                        if name == "en0" || name == "en1" {
                            preferredCandidate = ip
                            break
                        } else if fallbackCandidate == nil {
                            fallbackCandidate = ip
                        }
                    }
                }
            }
            ptr = interface.ifa_next
        }
        return preferredCandidate ?? fallbackCandidate
    }

    // MARK: - Server Lifecycle

    public func start(port: Int, allowLAN: Bool, authToken: String) {
        stop()

        let sanitizedPort = min(max(port, 1024), 65535)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(sanitizedPort)) else {
            lastError = "Invalid TCP port \(port)"
            return
        }

        let parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        if !allowLAN {
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        }

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            let newListener: NWListener
            if allowLAN {
                newListener = try NWListener(using: parameters, on: nwPort)
            } else {
                newListener = try NWListener(using: parameters)
            }

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        if let boundPort = newListener.port?.rawValue {
                            self.activePort = Int(boundPort)
                        } else {
                            self.activePort = sanitizedPort
                        }
                        self.lastError = nil
                        DiagnosticsLogger.note("WebSocket server listening on \(self.displayEndpointURL(allowLAN: allowLAN)) (LAN=\(allowLAN))")
                    case let .failed(error):
                        self.isRunning = false
                        self.lastError = error.localizedDescription
                        DiagnosticsLogger.note("WebSocket listener failed: \(error.localizedDescription)")
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.acceptConnection(connection, authToken: authToken)
                }
            }

            self.activePort = sanitizedPort
            self.listener = newListener
            newListener.start(queue: networkQueue)
        } catch {
            self.isRunning = false
            self.lastError = error.localizedDescription
            DiagnosticsLogger.note("Could not start WebSocket server: \(error.localizedDescription)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        for (_, session) in sessions {
            session.connection.cancel()
        }
        sessions.removeAll()
        connectedClientsCount = 0
        isRunning = false
    }

    // MARK: - Client Connections & Frame Loop

    private func acceptConnection(_ connection: NWConnection, authToken: String) {
        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let initiallyAuthed = trimmedToken.isEmpty
        let session = ClientSession(connection: connection, isAuthenticated: initiallyAuthed)
        let sessionID = session.id
        sessions[sessionID] = session
        connectedClientsCount = sessions.count

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    if initiallyAuthed {
                        let welcome = self.buildStateResponseJSON(event: "connected", requestID: nil, message: "Connected to WebCam Controller WebSocket Server")
                        self.sendText(welcome, on: connection)
                    } else {
                        let authPrompt = self.encodeJSON([
                            "ok": true,
                            "event": "auth_required",
                            "message": "Send {\"action\":\"auth\",\"token\":\"<token>\"} or include \"token\" in each request."
                        ])
                        self.sendText(authPrompt, on: connection)
                    }
                    self.receiveNextFrame(sessionID: sessionID)
                case .failed, .cancelled:
                    self.removeSession(sessionID)
                default:
                    break
                }
            }
        }

        connection.start(queue: networkQueue)
    }

    private func removeSession(_ id: UUID) {
        if let existing = sessions.removeValue(forKey: id) {
            existing.connection.cancel()
        }
        connectedClientsCount = sessions.count
    }

    private func receiveNextFrame(sessionID: UUID) {
        guard let session = sessions[sessionID] else { return }
        session.connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor [weak self] in
                guard let self, let activeSession = self.sessions[sessionID] else { return }
                if error != nil {
                    self.removeSession(sessionID)
                    return
                }

                if let wsMeta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
                   wsMeta.opcode == .close {
                    self.removeSession(sessionID)
                    return
                }

                if let data, !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    var authFlag = activeSession.isAuthenticated
                    let reply = self.handleIncomingMessage(text, clientAuthenticated: &authFlag)
                    activeSession.isAuthenticated = authFlag
                    self.sendText(reply, on: activeSession.connection)
                }

                self.receiveNextFrame(sessionID: sessionID)
            }
        }
    }

    private func sendText(_ text: String, on connection: NWConnection) {
        guard let data = text.data(using: .utf8) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws-text", metadata: [meta])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    public func broadcastStateSnapshot(event: String = "state_changed", message: String? = nil) {
        guard isRunning, !sessions.isEmpty else { return }
        let payload = buildStateResponseJSON(event: event, requestID: nil, message: message)
        for (_, session) in sessions where session.isAuthenticated {
            sendText(payload, on: session.connection)
        }
    }

    // MARK: - Command Processor (JSON & Plain-Text CLI Syntax)

    /// Processes a single incoming WebSocket message (JSON object or plain-text command) and returns a JSON response string.
    public func handleIncomingMessage(_ rawText: String, clientAuthenticated: inout Bool) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return encodeError("Empty WebSocket message", requestID: nil)
        }

        guard let mgr = manager else {
            return encodeError("CameraManager is not attached", requestID: nil)
        }

        let requiredToken = mgr.webSocketAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. JSON Request Mode
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let reqID = json["id"] as? String
            let action = ((json["action"] as? String) ?? (json["cmd"] as? String) ?? (json["type"] as? String) ?? "status")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let suppliedToken = (json["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if !requiredToken.isEmpty {
                if suppliedToken == requiredToken {
                    clientAuthenticated = true
                }
                if action == "auth" {
                    if clientAuthenticated {
                        return buildStateResponseJSON(event: "authenticated", requestID: reqID, message: "Authenticated")
                    }
                    return encodeError("Invalid authentication token", requestID: reqID)
                }
                guard clientAuthenticated else {
                    return encodeError("Unauthorized: valid token required", requestID: reqID)
                }
            } else if action == "auth" {
                clientAuthenticated = true
                return buildStateResponseJSON(event: "authenticated", requestID: reqID, message: "Authenticated (no token required)")
            }

            if let camSel = json["camera"] as? String, !camSel.isEmpty {
                guard let matched = mgr.findCamera(matching: camSel) else {
                    return encodeError("Camera not found: \(camSel)", requestID: reqID)
                }
                if mgr.selectedCameraRuntimeID != matched.identity.runtimeID {
                    mgr.selectedCameraRuntimeID = matched.identity.runtimeID
                }
            }

            return executeJSONAction(action, json: json, requestID: reqID, manager: mgr)
        }

        // 2. Plain-Text / URL Command Mode
        let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
        let verb = parts.first?.lowercased() ?? ""
        let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        if verb == "auth" {
            if requiredToken.isEmpty || rest == requiredToken {
                clientAuthenticated = true
                return buildStateResponseJSON(event: "authenticated", requestID: nil, message: "Authenticated")
            }
            return encodeError("Invalid authentication token", requestID: nil)
        }

        if !requiredToken.isEmpty && !clientAuthenticated {
            return encodeError("Unauthorized: send 'auth <token>' or JSON with \"token\"", requestID: nil)
        }

        if trimmed.lowercased().hasPrefix("webcamcontroller://"),
           let url = URL(string: trimmed),
           let parsed = ControllerURLCommand.parse(url) {
            let msg = mgr.execute(parsed.command, cameraSelector: parsed.camera)
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "command_executed", requestID: nil, message: msg)
        }

        return executePlainTextCommand(verb: verb, argumentString: rest, manager: mgr)
    }

    private func executeJSONAction(
        _ action: String,
        json: [String: Any],
        requestID: String?,
        manager mgr: CameraManager
    ) -> String {
        switch action {
        case "ping":
            var reply: [String: Any] = ["ok": true, "event": "pong"]
            if let requestID { reply["id"] = requestID }
            return encodeJSON(reply)

        case "status", "get", "state":
            return buildStateResponseJSON(event: "state", requestID: requestID, message: nil)

        case "list", "cameras":
            var reply: [String: Any] = [
                "ok": true,
                "event": "cameras",
                "cameras": mgr.cameras.enumerated().map { idx, cam in
                    cameraSummaryDict(cam, index: idx, isSelected: cam.identity.runtimeID == mgr.selectedCamera?.identity.runtimeID)
                }
            ]
            if let requestID { reply["id"] = requestID }
            return encodeJSON(reply)

        case "who", "call":
            var reply: [String: Any] = [
                "ok": true,
                "event": "call_status",
                "inCall": mgr.isSelectedCameraInCall,
                "elapsedSeconds": mgr.callElapsedSeconds,
                "formattedDuration": mgr.formattedCallDuration,
                "apps": mgr.activeCallApps.map { ["name": $0.name, "bundleID": $0.bundleID, "evidence": $0.evidence.rawValue] }
            ]
            if let requestID { reply["id"] = requestID }
            return encodeJSON(reply)

        case "set":
            guard let cam = mgr.selectedCamera else {
                return encodeError("No camera available", requestID: requestID)
            }
            var assignments: [(String, String)] = []
            if let ctrl = json["control"] as? String, let val = json["value"] {
                assignments.append((ctrl, "\(val)"))
            }
            if let dict = json["controls"] as? [String: Any] {
                for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                    assignments.append((k, "\(v)"))
                }
            }
            guard !assignments.isEmpty else {
                return encodeError("Missing 'control'/'value' or 'controls' dictionary in 'set' action", requestID: requestID)
            }
            var applied: [String] = []
            for (ctrl, val) in assignments {
                if cam.setVendorControl(id: ctrl, value: Int(val) ?? (val.lowercased() == "on" || val.lowercased() == "true" ? 1 : 0)) {
                    applied.append("\(ctrl)=\(val)")
                    continue
                }
                do {
                    let r = try cam.writeControl(ctrl, rawValue: val)
                    applied.append("\(r.id)=\(r.formattedDisplay)")
                } catch {
                    return encodeError("\(error)", requestID: requestID)
                }
            }
            let msg = "Remote WS set " + applied.joined(separator: ", ")
            mgr.statusMessage = msg
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "set_applied", requestID: requestID, message: msg)

        case "reset":
            guard let cam = mgr.selectedCamera else {
                return encodeError("No camera available", requestID: requestID)
            }
            if let ctrl = json["control"] as? String, !ctrl.isEmpty, ctrl.lowercased() != "all" {
                do {
                    let r = try cam.resetControl(ctrl)
                    let msg = "Remote WS reset \(r.id) to default (\(r.formattedDisplay))"
                    mgr.statusMessage = msg
                    lastCommandSummary = msg
                    broadcastStateSnapshot(event: "state_changed", message: msg)
                    return buildStateResponseJSON(event: "reset_applied", requestID: requestID, message: msg)
                } catch {
                    return encodeError("\(error)", requestID: requestID)
                }
            }
            cam.resetAllToHardwareDefaults()
            let msg = "Remote WS restored factory defaults on \(cam.identity.productName)"
            mgr.statusMessage = msg
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "reset_applied", requestID: requestID, message: msg)

        case "reset_view", "reset-view":
            let msg = mgr.execute(.resetView)
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "reset_view", requestID: requestID, message: msg)

        case "reset_image", "reset-image":
            let msg = mgr.execute(.resetImage)
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "reset_image", requestID: requestID, message: msg)

        case "look":
            guard let phrase = (json["phrase"] as? String) ?? (json["value"] as? String), !phrase.isEmpty else {
                return encodeError("Missing 'phrase' in 'look' action", requestID: requestID)
            }
            let msg = mgr.execute(.look(phrase))
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "look_applied", requestID: requestID, message: msg)

        case "stream":
            guard let cam = mgr.selectedCamera else {
                return encodeError("No camera available", requestID: requestID)
            }
            if let spec = (json["spec"] as? String) ?? (json["value"] as? String) {
                let lower = spec.lowercased()
                if lower == "default" || lower == "reset" {
                    _ = cam.resetStreamToDefault()
                } else if lower == "max" || lower == "natural" {
                    if let nat = UVCStreamValidator.naturalSelection(in: cam.streamModes) {
                        _ = cam.applyStreamSelection(nat)
                    }
                } else {
                    do {
                        _ = try cam.writeControl("stream", rawValue: spec)
                    } catch {
                        return encodeError("\(error)", requestID: requestID)
                    }
                }
            } else if let w = json["width"] as? Int, let h = json["height"] as? Int {
                let fps = (json["fps"] as? Int) ?? cam.selectedStream?.fps ?? 30
                let codecToken = (json["codec"] as? String) ?? (json["format"] as? String)
                let codec = codecToken.flatMap(UVCCameraDevice.parseCodecToken) ?? cam.selectedStream?.codec ?? .mjpeg
                guard let sel = UVCStreamValidator.validateSelection(
                    modes: cam.streamModes,
                    desiredCodec: codec,
                    desiredWidth: w,
                    desiredHeight: h,
                    desiredFPS: fps
                ), cam.applyStreamSelection(sel) else {
                    return encodeError("Could not apply stream \(w)x\(h)@\(fps)", requestID: requestID)
                }
            } else {
                return encodeError("Provide 'spec' (e.g. '1920x1080@60', 'max', 'default') or 'width'/'height'", requestID: requestID)
            }
            let summary = cam.selectedStream?.detailedSummary ?? "stream updated"
            let msg = "Remote WS stream -> \(summary)"
            mgr.statusMessage = msg
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "stream_applied", requestID: requestID, message: msg)

        case "preset":
            let sub = ((json["subaction"] as? String) ?? "apply").lowercased()
            let name = (json["name"] as? String) ?? (json["value"] as? String) ?? ""
            if sub == "save" {
                guard !name.isEmpty, let saved = mgr.saveCurrentSettingsAsPreset(name: name) else {
                    return encodeError("Provide a preset 'name' to save", requestID: requestID)
                }
                let msg = "Remote WS saved preset '\(saved.name)'"
                lastCommandSummary = msg
                broadcastStateSnapshot(event: "state_changed", message: msg)
                return buildStateResponseJSON(event: "preset_saved", requestID: requestID, message: msg)
            } else {
                guard !name.isEmpty else {
                    return encodeError("Provide a preset 'name' to apply", requestID: requestID)
                }
                let msg = mgr.execute(.preset(name))
                lastCommandSummary = msg
                broadcastStateSnapshot(event: "state_changed", message: msg)
                return buildStateResponseJSON(event: "preset_applied", requestID: requestID, message: msg)
            }

        case "config", "configuration":
            let stateStr = ((json["state"] as? String) ?? (json["value"] as? String) ?? "toggle").lowercased()
            let act: ControllerURLCommand.ConfigurationAction
            if let enabled = json["enabled"] as? Bool {
                act = enabled ? .on : .off
            } else {
                act = ControllerURLCommand.ConfigurationAction(rawValue: stateStr) ?? .toggle
            }
            let msg = mgr.execute(.configuration(act))
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "configuration_changed", requestID: requestID, message: msg)

        case "lock":
            let enabled: Bool
            if let b = json["enabled"] as? Bool {
                enabled = b
            } else if let s = (json["state"] as? String) ?? (json["value"] as? String) {
                enabled = (s.lowercased() == "on" || s.lowercased() == "true" || s == "1")
            } else {
                enabled = !mgr.isHardwareLockEnabled
            }
            let msg = mgr.execute(.lock(enabled))
            lastCommandSummary = msg
            broadcastStateSnapshot(event: "state_changed", message: msg)
            return buildStateResponseJSON(event: "lock_changed", requestID: requestID, message: msg)

        default:
            return encodeError("Unknown WebSocket action '\(action)'", requestID: requestID)
        }
    }

    private func executePlainTextCommand(verb: String, argumentString: String, manager mgr: CameraManager) -> String {
        switch verb {
        case "ping":
            return encodeJSON(["ok": true, "event": "pong"])
        case "get", "status", "state":
            return buildStateResponseJSON(event: "state", requestID: nil, message: nil)
        case "list", "cameras":
            return executeJSONAction("list", json: [:], requestID: nil, manager: mgr)
        case "who", "call":
            return executeJSONAction("who", json: [:], requestID: nil, manager: mgr)
        case "reset":
            return executeJSONAction("reset", json: argumentString.isEmpty ? [:] : ["control": argumentString], requestID: nil, manager: mgr)
        case "reset-view", "reset_view":
            return executeJSONAction("reset_view", json: [:], requestID: nil, manager: mgr)
        case "reset-image", "reset_image":
            return executeJSONAction("reset_image", json: [:], requestID: nil, manager: mgr)
        case "look":
            return executeJSONAction("look", json: ["phrase": argumentString], requestID: nil, manager: mgr)
        case "stream":
            return executeJSONAction("stream", json: ["spec": argumentString.isEmpty ? "default" : argumentString], requestID: nil, manager: mgr)
        case "config", "configuration":
            return executeJSONAction("config", json: ["state": argumentString.isEmpty ? "toggle" : argumentString], requestID: nil, manager: mgr)
        case "lock":
            return executeJSONAction("lock", json: ["state": argumentString.isEmpty ? "on" : argumentString], requestID: nil, manager: mgr)
        case "preset":
            let tokens = argumentString.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            if tokens.count == 2 && (tokens[0].lowercased() == "apply" || tokens[0].lowercased() == "save") {
                return executeJSONAction("preset", json: ["subaction": tokens[0].lowercased(), "name": tokens[1]], requestID: nil, manager: mgr)
            }
            return executeJSONAction("preset", json: ["name": argumentString], requestID: nil, manager: mgr)
        case "set":
            let pairs = argumentString.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            var controls: [String: String] = [:]
            for pair in pairs {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 {
                    controls[kv[0]] = kv[1]
                }
            }
            return executeJSONAction("set", json: ["controls": controls], requestID: nil, manager: mgr)
        default:
            return encodeError("Unknown command '\(verb)'. Try: status, list, set k=v, reset, stream 1920x1080@60, preset <name>, config on|off|toggle, lock on|off, look <phrase>", requestID: nil)
        }
    }

    // MARK: - JSON Serialization Helpers

    public func buildStateResponseJSON(event: String, requestID: String?, message: String?) -> String {
        guard let mgr = manager else {
            return encodeError("No manager attached", requestID: requestID)
        }

        var payload: [String: Any] = [
            "ok": true,
            "event": event,
            "version": AppBuildInfo.currentVersion,
            "configurationEnabled": mgr.isConfigurationEnabled,
            "hardwareLockEnabled": mgr.isHardwareLockEnabled,
            "inCall": mgr.isSelectedCameraInCall,
            "connectedClients": connectedClientsCount
        ]
        if let requestID { payload["id"] = requestID }
        if let message { payload["message"] = message }

        payload["cameras"] = mgr.cameras.enumerated().map { idx, cam in
            cameraSummaryDict(cam, index: idx, isSelected: cam.identity.runtimeID == mgr.selectedCamera?.identity.runtimeID)
        }

        if let cam = mgr.selectedCamera {
            var camDetail = cameraSummaryDict(cam, index: 0, isSelected: true)
            camDetail["controls"] = cam.readAllSupportedControls().map { $0.toJSONObject() }
            if !cam.vendorControls.isEmpty {
                camDetail["vendorControls"] = cam.vendorControls.map { vc in
                    [
                        "id": vc.id,
                        "name": vc.name,
                        "value": vc.current,
                        "formatted": vc.formattedValue,
                        "default": vc.defaultValue,
                        "min": vc.minimum,
                        "max": vc.maximum
                    ] as [String: Any]
                }
            }
            if let sel = cam.selectedStream {
                camDetail["selectedStream"] = [
                    "codec": sel.codec.shortTitle,
                    "width": sel.width,
                    "height": sel.height,
                    "fps": sel.fps,
                    "summary": sel.detailedSummary
                ]
            }
            camDetail["presets"] = mgr.presetsForSelectedCamera.map {
                [
                    "id": $0.id.uuidString,
                    "name": $0.name,
                    "loadAtStart": $0.loadAtStart
                ] as [String: Any]
            }
            payload["selectedCamera"] = camDetail
        }

        return encodeJSON(payload)
    }

    private func cameraSummaryDict(_ cam: UVCCameraDevice, index: Int, isSelected: Bool) -> [String: Any] {
        let id = cam.identity
        return [
            "index": index,
            "selected": isSelected,
            "name": id.productName,
            "vendor": id.vendorName,
            "vidPid": id.vidPidHex,
            "location": id.locationHex,
            "serial": id.serialNumber,
            "persistentID": id.persistentID,
            "runtimeID": id.runtimeID,
            "usbSpeed": id.usbSpeedTitle
        ]
    }

    private func encodeError(_ message: String, requestID: String?) -> String {
        var dict: [String: Any] = [
            "ok": false,
            "event": "error",
            "error": message
        ]
        if let requestID { dict["id"] = requestID }
        return encodeJSON(dict)
    }

    private func encodeJSON(_ dictionary: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"JSON encoding failed\"}"
        }
        return text
    }
}
