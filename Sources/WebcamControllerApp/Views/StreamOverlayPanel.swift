import AppKit
import Combine
import SwiftUI
import UVCCore

@MainActor
public final class StreamOverlayController {
    private let panel: NSPanel
    private var topEdgeY: CGFloat
    private var cancellable: AnyCancellable?

    public init(manager: CameraManager) {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 304, height: 210),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true

        let host = NSHostingView(rootView: StreamOverlayView(manager: manager))
        host.sizingOptions = [.preferredContentSize]
        p.contentView = host

        if !p.setFrameUsingName("WebCamControllerStreamOverlay"),
           let screen = NSScreen.main?.visibleFrame {
            p.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 324, y: screen.maxY - 24))
        }
        p.setFrameAutosaveName("WebCamControllerStreamOverlay")
        self.panel = p
        self.topEdgeY = p.frame.maxY

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: p,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.topEdgeY = self.panel.frame.maxY
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: p,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.frame.maxY != self.topEdgeY else { return }
                self.panel.setFrameTopLeftPoint(NSPoint(x: self.panel.frame.minX, y: self.topEdgeY))
            }
        }

        self.cancellable = manager.objectWillChange.sink { [weak self, weak manager] _ in
            Task { @MainActor in
                guard let self, let manager else { return }
                self.syncVisibility(shouldShow: manager.shouldDisplayFloatingOverlay)
            }
        }
        syncVisibility(shouldShow: manager.shouldDisplayFloatingOverlay)
    }

    public func syncVisibility(shouldShow: Bool) {
        guard shouldShow != panel.isVisible else { return }
        if shouldShow {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }
}

private struct OverlayWindowDragArea: NSViewRepresentable {
    final class DragNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> DragNSView { DragNSView() }
    func updateNSView(_ nsView: DragNSView, context: Context) {}
}

public struct StreamOverlayView: View {
    @ObservedObject var manager: CameraManager

    public init(manager: CameraManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar
            if !manager.isOverlayCollapsed {
                Group {
                    if let cam = manager.selectedCamera {
                        telemetryGrid(for: cam)
                    } else {
                        Text("No external USB UVC webcam connected")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 12)
        .padding(.vertical, manager.isOverlayCollapsed ? 8 : 11)
        .frame(width: manager.isOverlayCollapsed ? 264 : 304, alignment: .leading)
        .background(OverlayWindowDragArea())
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(manager.isSelectedCameraInCall ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(manager.isSelectedCameraInCall ? manager.activeCallAppSummary : "Camera Idle")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                if manager.isOverlayCollapsed, let cam = manager.selectedCamera {
                    let stream = (cam.liveHardwareStream ?? cam.selectedStream)?.shortSummary ?? "UVC Ready"
                    Text("\(stream) · \(cam.exposureTime.formattedShutterShort) · \(cam.whiteBalanceTemperature.current)K")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .allowsHitTesting(false)

            Spacer(minLength: 4)

            if !manager.isOverlayCollapsed && manager.isSelectedCameraInCall {
                Text(manager.formattedCallDuration)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }

            Button {
                manager.isOverlayCollapsed.toggle()
            } label: {
                Image(systemName: manager.isOverlayCollapsed ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                    .font(.system(size: 12.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(manager.isOverlayCollapsed ? "Expand stream telemetry" : "Collapse to one line")

            Button {
                manager.isOverlayDismissedForSession = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide overlay until next call")
        }
    }

    private func telemetryGrid(for cam: UVCCameraDevice) -> some View {
        let streamSummary = (cam.liveHardwareStream ?? cam.selectedStream)?.detailedSummary ?? "Default USB Mode"
        let expSummary = [
            cam.autoExposureMode.isSupported ? cam.autoExposureMode.current.shortTitle : nil,
            cam.exposureTime.isSupported ? cam.exposureTime.formattedShutterShort : nil,
            cam.gain.isSupported ? "Gain \(cam.gain.current)" : nil
        ].compactMap { $0 }.joined(separator: " · ")

        let wbSummary = [
            cam.whiteBalanceAuto.isSupported ? (cam.whiteBalanceAuto.current ? "Auto" : "Manual") : nil,
            cam.whiteBalanceTemperature.isSupported ? "\(cam.whiteBalanceTemperature.current)K" : nil
        ].compactMap { $0 }.joined(separator: " · ")

        let opticsSummary = [
            cam.focusAuto.isSupported ? (cam.focusAuto.current ? "AF" : "MF \(cam.focusAbsolute.current)") : nil,
            cam.zoomAbsolute.isSupported ? "Zoom \(cam.zoomAbsolute.formattedZoomShort)" : nil,
            cam.powerLineFrequency.isSupported ? (PowerLineFrequency(rawValue: cam.powerLineFrequency.current)?.title ?? "") : nil
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            overlayRow("Camera", cam.identity.productName)
            overlayRow("Stream", streamSummary)
            if let fixedFrom = manager.upgradedSlowModeFrom {
                GridRow {
                    Text("Fixed").foregroundStyle(.secondary)
                    Text("upgraded from \(fixedFrom)").foregroundStyle(.green).lineLimit(1)
                }
            }
            Divider().gridCellColumns(2)
            overlayRow("Exposure", expSummary)
            overlayRow("Color", wbSummary)
            if !opticsSummary.isEmpty {
                overlayRow("Optics", opticsSummary)
            }
        }
    }

    private func overlayRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "N/A" : value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
        }
    }
}
