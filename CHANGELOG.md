# Changelog

All notable changes to **MacOS WebCam Controller** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-11-04

### Added
- **Logarithmic EV-Stop Exposure Time Slider (`log2`Stops)**: Manual shutter tuning in `Basic` and the Menu Bar popover now scales smoothly in photographic EV stops (`1/1000s` → `1/250s` → `1/125s` → `1/60s` → `1/30s`) instead of compressing fast shutter speeds into the left edge of a linear `100 µs` range.
- **One-Click Floating Stream HUD Button in Menu Bar (`pip`)**: Toggle or bring back a dismissed floating call stats overlay directly from the Menu Bar header.
- **16:9 Aspect-Ratio Priority in Slow-Mode (`5 fps`) Call Auto-Fix**: Prefers `1920×1080` → `1280×720` → `2560×1440` widescreen modes (`>= 24 fps`) when upgrading sluggish `<= 10 fps` call streams.
- **Automated Tag Release Workflow, Camera Issue Form & Contributor Guide**: Added `.github/workflows/release.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`, and `CONTRIBUTING.md`.

## [1.1.0] - 2026-11-04

### Added
- **Homebrew Tap & Cask Installation (`brew`)**: Install and update both **`WebCam Controller.app`** and the **`webcamctl`** CLI from a single command:
  ```bash
  brew install --cask SilverFeit/tap/macos-webcam-controller
  ```
- **Bundled `webcamctl` Command-Line Interface**: Full terminal and script automation (`list`, `describe [--raw]`, `get`, `set`, `reset`, `stream`, `preset`, `lock`, `who`, `sessions`, `check-update`, `version`, `--camera`, and `--json`), with live synchronization back to the running Menu Bar app via `DistributedNotificationCenter`.
- **Bottom Version Badge & Live GitHub Release Update Checker**: Both the Menu Bar popover and `Webcam Settings Panel` display the active app version (`v1.1.0 · GitHub ↗`) at the bottom, check GitHub Releases for newer versions, and surface a one-click **`Update vX.Y.Z · GitHub ↗`** pill whenever an update is available.
- **Zero-Permission Live Call Detection & Client App Attribution**: Uses `CoreMediaIO` (`kCMIODevicePropertyDeviceIsRunningSomewhere`) and `CoreAudio` (`kAudioProcessPropertyIsRunningInput`) to detect active calls and identify apps (Zoom, FaceTime, Teams, OBS, Meet, WhatsApp) with **zero Camera or Microphone TCC permissions**.
- **Automatic Slow-Mode (`5 fps`) Call Stream Fix**: Automatically detects when video apps (such as WhatsApp) negotiate sluggish `<= 10 fps` uncompressed modes and upgrades the stream to smooth `1080p @ 30 fps` MJPEG.
- **Floating Non-Activating Stream Stats HUD**: Optional draggable floating overlay (`Off` / `While in Call` / `Always`) showing live resolution, FPS, shutter speed (`1/60s`), white balance (`K`), call duration, and active app without stealing keyboard focus.
- **Photographic Shutter & Optical Zoom Readouts**: Displays exposure time in standard shutter notation (`1/60s`, `1/50s`, `1/30s`) and accepts fractional shutter inputs (`webcamctl set shutter=1/60`), plus optical zoom multipliers (`1.3×`).
- **Firmware, Extension Unit & Raw Descriptor Introspection**: Reads USB `bcdDevice` firmware revisions, UVC `VC_EXTENSION_UNIT` GUIDs/bitmaps, and raw USB configuration hex dumps (`webcamctl describe --raw`).
- **Bounded Diagnostics Log & CI**: Rotating 1 MB hardware diagnostics log at `~/Library/Logs/WebCamController.log` with human-readable IOKit status decoding, plus automated GitHub Actions CI for `WebcamControllerApp`, `webcamctl`, and `UVCCoreTests`.

### Fixed
- **UVC `< 1.5` Anti-Flicker Stall Guard**: Clamps `PowerLineFrequency` maximum to `60 Hz (2)` on UVC 1.0/1.1 cameras whose firmware advertises `Auto (3)` in `GET_MAX` but stalls Endpoint 0 on `SET_CUR`.
- **Interface-First VideoStreaming Control Transfers**: Attempts non-exclusive `IOUSBInterfaceInterface->ControlRequest` on `SC_VIDEOSTREAMING` before falling back to `DeviceRequest`, improving compatibility across USB hubs and composite UVC webcams.

## [1.0.0] - 2026-11-04

### Added
- Native macOS Menu Bar app (`LSUIElement`) and floating `Webcam Settings Panel` (`Basic`, `Advanced`, `Preferences`) built in Swift + C IOKit (`IOUSBDeviceInterface` Endpoint 0).
- Real-time hardware control over Auto-Exposure Mode, Exposure Time, Gain, Brightness, Contrast, Hue, Saturation, Sharpness, Gamma, White Balance Temperature (`K`), Anti-Flicker (`Off` / `50 Hz` / `60 Hz` / `Auto`), Backlight Compensation, Low-Light Priority, Focus, Zoom, Pan, and Tilt.
- Punctual per-control hardware rollback (`↺`) restoring factory `GET_DEF` register defaults without disturbing other settings.
- Validated UVC VideoStreaming format/resolution/FPS matrix (`MJPEG` / `Uncompressed YUY2` / `H.264`, up to `2K QHD` / `4K UHD` and `60 fps`).
- Anti-Reset Hardware Lock daemon (`2.5s` drift enforcement) and persistent per-camera-ID presets (`Load at Start`).
