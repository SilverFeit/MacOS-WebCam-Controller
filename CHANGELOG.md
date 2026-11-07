# Changelog

All notable changes to **MacOS WebCam Controller** are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-11-06

### Added
- **WebSocket Remote Network Camera Control (`ws://host:port`)**: Built-in `Network.framework` (`NWListener` + `NWProtocolWebSocket`) server configurable in **Preferences** and **Advanced** (`ws://127.0.0.1:8765` or LAN `ws://<LAN-IP>:8765`, optional Auth Token) plus `webcamctl ws [status|on|off|port <n>|lan <on|off>|token <secret|none>]`. Supports real-time JSON and plain-text commands (`status`, `list`, `set`, `reset`, `reset_view`, `reset_image`, `stream`, `preset`, `config`, `lock`, `look`, `who`, `ping`) and broadcasts live `state_changed` events to connected clients.
- **Menu Bar Context Menu (right-click / double-click)**: replaces the old shortcut to `Advanced` with four entries — **Turn Configuration Off / On**, **Open Advanced…**, **About WebCam Controller**, **Quit WebCam Controller**.
- **Configuration On/Off**: parks your saved values and restores the camera's factory defaults, then re-applies them when turned back on. The Anti-Reset Lock and startup presets stand down while it is off. Available from the context menu, a power button in the Menu Bar popover, `webcamctl config on|off|toggle|status`, `webcamcontroller://config/…`, WebSocket, and a global shortcut. A `Config OFF` badge shows in the bottom bar and the menu bar icon dims.
- **License Line in `Advanced` and About Panel**: *Released under the [MIT License](https://github.com/SilverFeit/MacOS-WebCam-Controller/blob/main/LICENSE). Copyright © 2026 [SilverFeit](https://github.com/SilverFeit).* with clickable links to the repository `LICENSE` and the author.
- **Interactive 2D PTZ Framing Pad (`FramingPadView`)**: Drag the 16:9 crop viewport in `Advanced` to pan and tilt simultaneously in a single 8-byte Endpoint 0 transfer, double-click to reset view (`Zoom`, `Pan`, `Tilt`), or right-click for quick reset actions.
- **Vendor Extension Unit (XU) Hardware Profiles**: Bundled profiles for Insta360 Link series, Anker PowerConf C200, and AnkerWork C310 (HDR, Field of View `65°`/`78°`/`95°`, EV compensation, Face Auto-Focus/Exposure, AI Mic Noise Reduction) plus custom JSON profiles in `~/Library/Application Support/WebCamController/Profiles/`.
- **Natural-Language Look Adjustment & Scoped Resets**: `webcamctl look "<phrase>"` and `webcamcontroller://look/<phrase>` (e.g. `"warmer, more contrast"`, `"black and white"`, `"natural"`), plus `webcamctl reset-view` and `webcamctl reset-image`.
- **`webcamcontroller://` URL Scheme**: `preset/<name|n|default>`, `config/on|off|toggle`, `lock/on|off`, `reset`, `reset-view`, `reset-image`, `look/<phrase>`, `camera/<name>`, `set?control=value&…`, plus `?camera=` — usable from Shortcuts, Raycast, Stream Deck and `open -g`.
- **Optional Global Shortcuts (Carbon, no permissions)**: `⌃⌥⌘0` toggles your configuration, `⌃⌥⌘1`–`⌃⌥⌘5` apply presets 1–5.
- **Camera Report**: `Preferences → Copy Camera Report` and `webcamctl report` produce a paste-ready Markdown report (identity, USB link, descriptor units, control ranges, video modes) and open the bug report form.
- **Preset Export / Import**: `Preferences → Export… / Import…`, `webcamctl preset export|import` — portable JSON, duplicate names are numbered and `Load at Start` is never imported.
- **USB Link Check**: reads `bcdUSB` and the negotiated link speed; warns when a USB 3 camera is running at USB 2 speed. Shown in the panel, `Preferences`, `webcamctl describe` and `webcamctl list --json`.
- **Double-click a slider label to reset it** to the camera default.

### Changed
- **Serialized, Rate-Limited Endpoint 0 Transfers**: every control request of every camera shares one lock with a minimum gap, protecting firmwares that stall under bursts (slider drags, lock re-assertion, CLI).
- **Forbidden Extension Selector Guard**: writes to known firmware / USB-mode-switch extension selectors are refused at the lowest level.
- **Highest-Rate Natural Mode Selection (`UVCStreamValidator.naturalSelection`)**: Selects the highest resolution with `>= 30 fps` (`16:9` preferred) and the highest frame rate at that resolution (`60 fps` over `30 fps`).

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
