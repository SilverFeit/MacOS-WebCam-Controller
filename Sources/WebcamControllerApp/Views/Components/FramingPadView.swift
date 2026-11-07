import SwiftUI
import UVCCore

/// Interactive 2D 16:9 optical framing pad for UVC cameras that support Pan, Tilt, or Zoom.
/// Dragging inside the pad moves Pan & Tilt simultaneously over USB Endpoint 0; double-clicking resets the view.
public struct FramingPadView: View {
    @ObservedObject var camera: UVCCameraDevice

    public init(camera: UVCCameraDevice) {
        self.camera = camera
    }

    private var activeZoom: NumericRangeControlState {
        camera.zoomAbsolute.isSupported ? camera.zoomAbsolute : camera.digitalMultiplier
    }

    private var isInteractive: Bool {
        (camera.panAbsolute.isSupported && camera.panAbsolute.canSet) ||
        (camera.tiltAbsolute.isSupported && camera.tiltAbsolute.canSet) ||
        (activeZoom.isSupported && activeZoom.canSet)
    }

    private var isViewModified: Bool {
        (activeZoom.isSupported && activeZoom.current != activeZoom.defaultValue) ||
        (camera.panAbsolute.isSupported && camera.panAbsolute.current != camera.panAbsolute.defaultValue) ||
        (camera.tiltAbsolute.isSupported && camera.tiltAbsolute.current != camera.tiltAbsolute.defaultValue) ||
        (camera.rollAbsolute.isSupported && camera.rollAbsolute.current != camera.rollAbsolute.defaultValue)
    }

    /// Normalized zoom factor `0.0` (wide) ... `1.0` (max telephoto).
    private var zoomFraction: Double {
        guard activeZoom.isSupported, activeZoom.maximum > activeZoom.minimum else { return 0.0 }
        return min(max(Double(activeZoom.current - activeZoom.minimum) / Double(activeZoom.maximum - activeZoom.minimum), 0.0), 1.0)
    }

    /// Normalized pan `-1.0` (left) ... `+1.0` (right).
    private var panNormalized: Double {
        guard camera.panAbsolute.isSupported, camera.panAbsolute.maximum > camera.panAbsolute.minimum else { return 0.0 }
        let mid = Double(camera.panAbsolute.minimum + camera.panAbsolute.maximum) / 2.0
        let halfSpan = Double(camera.panAbsolute.maximum - camera.panAbsolute.minimum) / 2.0
        guard halfSpan > 0 else { return 0.0 }
        return min(max((Double(camera.panAbsolute.current) - mid) / halfSpan, -1.0), 1.0)
    }

    /// Normalized tilt `-1.0` (down) ... `+1.0` (up).
    private var tiltNormalized: Double {
        guard camera.tiltAbsolute.isSupported, camera.tiltAbsolute.maximum > camera.tiltAbsolute.minimum else { return 0.0 }
        let mid = Double(camera.tiltAbsolute.minimum + camera.tiltAbsolute.maximum) / 2.0
        let halfSpan = Double(camera.tiltAbsolute.maximum - camera.tiltAbsolute.minimum) / 2.0
        guard halfSpan > 0 else { return 0.0 }
        return min(max((Double(camera.tiltAbsolute.current) - mid) / halfSpan, -1.0), 1.0)
    }

    public var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let padW = geo.size.width
                let padH = geo.size.height
                // Viewport box shrinks as zoom increases (1.0x -> 82% of pad, max zoom -> 34% of pad)
                let scale = max(0.34, 0.82 - zoomFraction * 0.48)
                let boxW = padW * scale
                let boxH = padH * scale
                let maxTravelX = max(1.0, (padW - boxW) / 2.0)
                let maxTravelY = max(1.0, (padH - boxH) / 2.0)
                let offsetX = panNormalized * maxTravelX
                // Positive UVC tilt is up, which is negative Y in SwiftUI coordinates
                let offsetY = -tiltNormalized * maxTravelY

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                        )

                    // Subtle rule-of-thirds / crosshair grid
                    Path { path in
                        path.move(to: CGPoint(x: padW / 2, y: 4))
                        path.addLine(to: CGPoint(x: padW / 2, y: padH - 4))
                        path.move(to: CGPoint(x: 4, y: padH / 2))
                        path.addLine(to: CGPoint(x: padW - 4, y: padH / 2))
                    }
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))

                    // Active 16:9 crop box
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(isViewModified ? Color.accentColor : Color.secondary.opacity(0.65), lineWidth: 1.4)
                        )
                        .frame(width: boxW, height: boxH)
                        .offset(x: offsetX, y: offsetY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            guard isInteractive else { return }
                            let normX = min(max((gesture.location.x - padW / 2.0) / maxTravelX, -1.0), 1.0)
                            let normY = min(max(-((gesture.location.y - padH / 2.0) / maxTravelY), -1.0), 1.0)

                            let targetPan: Int = {
                                guard camera.panAbsolute.isSupported else { return 0 }
                                let mid = Double(camera.panAbsolute.minimum + camera.panAbsolute.maximum) / 2.0
                                let half = Double(camera.panAbsolute.maximum - camera.panAbsolute.minimum) / 2.0
                                return Int((mid + normX * half).rounded())
                            }()
                            let targetTilt: Int = {
                                guard camera.tiltAbsolute.isSupported else { return 0 }
                                let mid = Double(camera.tiltAbsolute.minimum + camera.tiltAbsolute.maximum) / 2.0
                                let half = Double(camera.tiltAbsolute.maximum - camera.tiltAbsolute.minimum) / 2.0
                                return Int((mid + normY * half).rounded())
                            }()
                            _ = camera.setPanTiltAbsolute(pan: targetPan, tilt: targetTilt)
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        camera.resetViewToDefaults()
                    }
                )
                .contextMenu {
                    Button("Reset View (Zoom, Pan, Tilt)") {
                        camera.resetViewToDefaults()
                    }
                    Button("Reset Image Controls") {
                        camera.resetImageToDefaults()
                    }
                    Divider()
                    Button("Restore All Hardware Defaults") {
                        camera.resetAllToHardwareDefaults()
                    }
                }
            }
            .frame(width: 108, height: 61)
            .help("Drag to pan & tilt in 2D · Double-click to reset view (Zoom, Pan, Tilt)")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isViewModified ? Color.accentColor : .secondary)
                    Text("2D PTZ Framing Pad")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button("Reset View") {
                        camera.resetViewToDefaults()
                    }
                    .controlSize(.mini)
                    .disabled(!isViewModified)
                }

                Text("Drag viewport to pan/tilt simultaneously · Double-click pad to center.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("Zoom: \(activeZoom.isSupported ? activeZoom.formattedZoomShort : "1.0x")")
                    Text("Pan: \(camera.panAbsolute.isSupported ? camera.panAbsolute.formattedArcsecondsDegrees : "0°")")
                    Text("Tilt: \(camera.tiltAbsolute.isSupported ? camera.tiltAbsolute.formattedArcsecondsDegrees : "0°")")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
