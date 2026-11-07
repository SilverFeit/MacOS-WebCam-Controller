import AppKit
import SwiftUI
import UVCCore

public struct AppVersionFooterView: View {
    @ObservedObject var manager: CameraManager
    @ObservedObject var checker: UpdateChecker
    let showStatusText: Bool

    public init(manager: CameraManager, showStatusText: Bool = true) {
        self.manager = manager
        self.checker = manager.updateChecker
        self.showStatusText = showStatusText
    }

    public var body: some View {
        HStack(spacing: 6) {
            if showStatusText {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6.5, height: 6.5)

                Text(leadingStatusLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(manager.isSelectedCameraInCall ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if !manager.isConfigurationEnabled {
                Label("Config OFF", systemImage: "power")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .help("Your configuration is turned off — the camera runs on its factory defaults.")
            }

            if manager.isHardwareLockEnabled {
                Label("Locked", systemImage: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            // Version + GitHub Redirect + Live Update Badge
            if checker.isUpdateAvailable, let latest = checker.latestRelease {
                Button {
                    NSWorkspace.shared.open(latest.htmlURL)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("Update v\(latest.versionString) · GitHub")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.06, green: 0.62, blue: 0.92), Color(red: 0.08, green: 0.72, blue: 0.54)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("New release v\(latest.versionString) is available on GitHub (installed: v\(checker.currentVersion)). Click to download or run `\(AppBuildInfo.homebrewUpgradeCommand)`.")
            } else {
                HStack(spacing: 4) {
                    Button {
                        NSWorkspace.shared.open(checker.releasesRedirectURL)
                    } label: {
                        HStack(spacing: 3.5) {
                            Text("v\(checker.currentVersion) · GitHub")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("MacOS WebCam Controller v\(checker.currentVersion) — Open GitHub Repository & Releases")

                    Button {
                        Task {
                            await checker.checkForUpdates(force: true)
                            if checker.isUpdateAvailable, let rel = checker.latestRelease {
                                manager.statusMessage = "New version v\(rel.versionString) available on GitHub"
                            } else {
                                manager.statusMessage = "Up to date (v\(checker.currentVersion))"
                            }
                        }
                    } label: {
                        Image(systemName: checker.isChecking ? "ellipsis.circle" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(checker.isChecking)
                    .help("Check GitHub Releases for updates")
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private var statusDotColor: Color {
        if manager.isSelectedCameraInCall {
            return Color.green
        }
        return manager.selectedCamera != nil ? Color.accentColor : Color.orange
    }

    private var leadingStatusLabel: String {
        if manager.isSelectedCameraInCall {
            let streamText = (manager.selectedCamera?.liveHardwareStream ?? manager.selectedCamera?.selectedStream)
                .map { "\($0.width)×\($0.height)@\($0.fps)fps" } ?? "Live"
            return "Live: \(manager.activeCallAppSummary) · \(streamText) (\(manager.formattedCallDuration))"
        }
        return manager.statusMessage
    }
}
