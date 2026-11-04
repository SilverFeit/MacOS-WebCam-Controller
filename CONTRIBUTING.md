# Contributing to MacOS WebCam Controller

Bug reports, USB camera compatibility reports, and pull requests are welcome!

## Build & Verify Locally

Requires macOS 14+ on Apple Silicon (`arm64`) with Xcode or Xcode Command Line Tools (`swift 6.0+`):

```bash
swift build
swift run UVCCoreTests
./Scripts/build_app.sh
```

## Architecture Layout

- `Sources/CUVCHardware` — C11 `IOKit` / `IOUSBLib` layer for non-exclusive UVC Endpoint 0 control requests, `VC_EXTENSION_UNIT` parsing, and raw USB configuration descriptor access.
- `Sources/UVCCore` — Swift 6 device introspection, validated resolution/FPS matrix, CLI command bridge, zero-permission call telemetry (`CoreMediaIO` + `CoreAudio`), presets, and GitHub Releases update checker.
- `Sources/WebcamControllerApp` — Native AppKit Menu Bar item (`LSUIElement`), `Webcam Settings Panel`, and floating non-activating Stream Stats HUD.
- `Sources/webcamctl` — Bundled command-line interface (`list`, `describe`, `get`, `set`, `reset`, `stream`, `preset`, `lock`, `who`, `sessions`, `check-update`, `version`).
- `Tests/UVCCoreTests` — Unit and live USB UVC hardware verification suite.

## Reporting a USB Webcam

Because UVC firmware varies across manufacturers, sharing the output of:

```bash
webcamctl list
webcamctl describe
```

along with your macOS version in a GitHub Issue helps verify control ranges, Extension Unit GUIDs, and supported `SC_VIDEOSTREAMING` frame intervals.
