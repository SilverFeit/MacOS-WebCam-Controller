<div align="center">

<img src="docs/assets/app-icon.png" alt="MacOS WebCam Controller Icon" width="118" height="118" />

# MacOS WebCam Controller

**Direct USB UVC Hardware Control from the macOS Menu Bar & CLI (`webcamctl`) — Zero Virtual Cameras · 0% Video CPU Overhead**

[![Release](https://img.shields.io/github/v/release/SilverFeit/MacOS-WebCam-Controller?style=flat-square&label=Download&color=0ea5e9)](https://github.com/SilverFeit/MacOS-WebCam-Controller/releases/latest)
[![Homebrew](https://img.shields.io/badge/Homebrew-SilverFeit%2Ftap-fbb040?style=flat-square&logo=homebrew&logoColor=white)](#installation)
[![Platform](https://img.shields.io/badge/macOS-14%2B%20(Apple%20Silicon)-111827?style=flat-square&logo=apple)](https://github.com/SilverFeit/MacOS-WebCam-Controller/releases/latest)
[![Protocol](https://img.shields.io/badge/USB-UVC%201.0%20%E2%80%93%201.5%20(IOKit%20EP0)-10b981?style=flat-square)](#how-direct-usb-hardware-control-works)
[![Privacy](https://img.shields.io/badge/Permissions-Zero%20Camera%20%2F%20Mic%20Access-22c55e?style=flat-square)](#privacy--security-by-design)
[![License](https://img.shields.io/badge/License-MIT-6366f1?style=flat-square)](LICENSE)

```bash
brew install --cask SilverFeit/tap/macos-webcam-controller
```

[**Install via Homebrew**](#option-a--homebrew-recommended) · [**Download `.dmg`**](https://github.com/SilverFeit/MacOS-WebCam-Controller/releases/latest) · [**CLI (`webcamctl`)**](#command-line-interface-webcamctl) · [**Features**](#key-features) · [**Architecture**](#how-direct-usb-hardware-control-works) · [**User Guide**](docs/USER_GUIDE.md) · [**Español**](#-español--resumen-del-proyecto)

<br />

<img src="docs/assets/hero-banner.png" alt="MacOS WebCam Controller — Menu Bar Popover, Basic & Advanced UVC Hardware Panels" width="100%" />

</div>

---

## Overview

**MacOS WebCam Controller** is a lightweight native macOS Menu Bar app + CLI (`Swift` + `SwiftUI` + `C / IOKit`) that unlocks **physical sensor and ISP hardware registers** on external USB webcams compliant with the **UVC (USB Video Class)** standard.

On Windows, operating system APIs (`DirectShow` / `IAMCameraControl`) expose every USB webcam's hardware control panel out of the box. On macOS, `AVFoundation` captures video frames from external USB cameras while ignoring their UVC control descriptors (`isExposureModeSupported(.custom)` returns `false`, and `uvcassistantextension` hides UVC control entities). As a result, most Mac tools resort to heavy **virtual cameras** that apply software filters on top of an already overexposed, motion-blurred, or color-shifted image.

**MacOS WebCam Controller takes the pure hardware path:** it communicates directly with your webcam's internal sensor and Image Signal Processor (ISP) over **USB Endpoint 0** via `IOKit` (`IOUSBLib`) in real time — while **Zoom, OBS Studio, Microsoft Teams, Google Meet, Webex, WhatsApp, FaceTime, or Chrome** continue consuming the native camera feed with **zero virtual cameras, zero Camera/Microphone TCC permissions, zero video latency, and 0% video re-encoding CPU/GPU drain**.

<details>
<summary><strong>🇪🇸 Español — Resumen del Proyecto (Haz clic para desplegar)</strong></summary>

<br />

**MacOS WebCam Controller** es una aplicación nativa para la barra de menús de macOS + herramienta CLI (`webcamctl`) diseñada para modificar **físicamente los registros internos del sensor y del procesador de imagen (ISP)** de cualquier cámara web externa USB compatible con **UVC (USB Video Class)**.

- **Instalación Directa por Homebrew (`brew`):** Instala tanto **`WebCam Controller.app`** como el comando de terminal **`webcamctl`** con `brew install --cask SilverFeit/tap/macos-webcam-controller` y actualiza con `brew upgrade --cask macos-webcam-controller`.
- **100% Hardware Real (Sin Cámaras Virtuales ni Permisos):** En Zoom, Meet, Teams, OBS, WhatsApp o FaceTime sigues eligiendo el nombre real de tu cámara USB. La app inyecta paquetes UVC (`SET_CUR`, `GET_CUR`, `GET_DEF`) por **Endpoint 0** mediante `IOKit` sin pedir permisos de Cámara/Micrófono y con `0%` de carga de recodificación de video.
- **Control Total + Obturación Fotográfica (`1/60s`):** Exposición manual, velocidad de obturación en formato fotográfico (`1/60s`, `1/50s`), ganancia/ISO, temperatura en Kelvin, brillo, contraste, matiz, saturación, nitidez, gamma, filtro anti-parpadeo (`50 Hz / 60 Hz`) con protección contra bloqueos UVC `< 1.5`, contraluz, enfoque y PTZ (`1.3×` Zoom, Pan, Tilt).
- **Resoluciones (2K / 4K / 1080p), FPS Validados y Auto-Fix de Llamadas a `5 fps`:** Valida combinaciones reales `(Formato, Resolución, FPS)` desde los descriptores USB y mejora automáticamente llamadas lentas (`<= 10 fps`, como WhatsApp) a `1080p @ 30 fps`.
- **HUD Flotante, CLI `webcamctl` y Versionamiento inferior con GitHub:** Incluye HUD flotante opcional durante llamadas, control total por terminal (`webcamctl set shutter=1/60 kelvin=4500`, `webcamctl stream 2k 30`, `webcamctl who`) y barra inferior con la versión actual (`v1.1.1 · GitHub ↗`) y aviso automático cuando hay una actualización disponible en GitHub Releases.

</details>

---

## Why Direct Hardware Beats Virtual Cameras

| Capability | **MacOS WebCam Controller** *(Direct USB UVC)* | Virtual Camera Software *(`CMIOExtension`)* |
| :--- | :--- | :--- |
| **Where adjustments happen** | **Inside the camera's physical CMOS sensor & ISP chip** before frames enter the USB cable | Post-processed in software after frames are already compressed & clipped |
| **Motion blur & blown highlights** | **True electronic shutter control** (`1/60s`, `1/125s`) eliminates motion blur optically | Cannot recover clipped highlights or remove sensor motion blur |
| **CPU / GPU / Battery impact** | **~0.0%** — zero video frames decoded, filtered, or re-encoded | Continuous CPU/GPU frame copying & shader rendering during calls |
| **Added video latency** | **0 ms** | 1–3 frames of pipeline buffering |
| **Device selected in Zoom / OBS / Meet** | **Your real USB webcam directly** | A synthetic *"Virtual Camera"* wrapper (often blocked in proctoring/enterprise apps) |
| **macOS Permissions & System Extensions** | **None required** (zero Camera, zero Mic, zero System Extension) | Requires Camera TCC permission + System Extension approval |
| **CLI & Script Automation** | **Bundled `webcamctl` CLI** (`--json`, Raycast/Shortcuts/Stream Deck ready) | GUI-only |

---

## Key Features

<div align="center">
<img src="docs/assets/panel-basic-advanced.png" alt="Webcam Settings Panel — Basic and Advanced Tabs" width="100%" />
</div>

### 1. Instant Menu Bar Control + Standalone Settings Panel + Bottom GitHub Version Bar
- **Left-click** the webcam icon in the macOS Menu Bar to adjust primary exposure, photographic shutter (`1/60s`), color, and white-balance sliders on the fly during a call.
- **Right-click** the Menu Bar icon (or click **Advanced…** / **Panel**) to open the full **Webcam Settings Panel** (`Basic`, `Advanced`, and `Preferences` tabs), with optional **Pin on Top** so it floats above OBS, Zoom, or Photo Booth.
- **Live Version & Update Badge at the Bottom:** Both the Menu Bar popover and Settings Panel display your installed version (`v1.1.1 · GitHub ↗`) at the bottom. When a newer release is published on GitHub, the badge highlights as **`⬆ Update vX.Y.Z · GitHub ↗`** for one-click access to the latest release.

### 2. Full Sensor, ISP & Optical Control (`Basic` & `Advanced`)
- **Exposure & Photographic Shutter (`1/60s`):** Switch between hardware-supported `Manual`, `Auto`, `Shutter Priority`, and `Aperture Priority` modes; dial in exact physical **Exposure Time** displayed in standard shutter fractions (`1/60s`, `1/50s`, `1/30s`) and sensor **Gain**.
- **Color & Tone ISP Pipeline:** Hardware **Brightness**, **Contrast**, **Hue**, **Saturation**, **Sharpness**, and **Gamma**.
- **Precision White Balance:** Toggle **Auto** off to lock exact color temperature in **Kelvin** (e.g. `3200K` tungsten to `6500K` daylight).
- **Lighting & Optics:** **Power Line Frequency** (`Disabled`, `50 Hz`, `60 Hz`, `Auto` — with automatic Endpoint 0 stall protection on UVC `< 1.5` cameras), **Backlight Compensation** (switch + multi-level fine slider), **Low Light Compensation** (`AE Priority`), **Focus** (`Auto` + manual optical focus), **Optical/Digital Zoom** (`1.3×`), **Pan**, **Tilt**, **Aperture**, **Roll**, **Hardware Privacy Shutter**, and **Progressive Scan**.

### 3. Hardware Resolutions, Validated FPS Matrix & Automatic `5 fps` Call Fix
- Reads raw `SC_VIDEOSTREAMING (0x02)` USB descriptors (`MJPEG`, `Uncompressed YUY2`, `H.264`) to list every real hardware resolution (`4K UHD`, `2K QHD 2560×1440`, `1080p FHD`, `UXGA`, `720p HD`, `VGA`) and enables **only** frame rates physically supported at that resolution.
- **Automatic Slow-Mode (`5 fps`) Call Upgrade:** Apps like WhatsApp Desktop often pick a webcam's highest uncompressed resolution at a choppy `5 fps`. When enabled in `Preferences`, **MacOS WebCam Controller** detects `<= 10 fps` live streams within 2 seconds of call start and automatically negotiates smooth `1080p @ 30 fps` MJPEG.

### 4. Zero-Permission Call Detection & Floating Stream Stats HUD
- Passively monitors `CoreMediaIO` (`kCMIODevicePropertyDeviceIsRunningSomewhere`) and `CoreAudio` active client processes to show **which app is using your webcam** (`Zoom`, `FaceTime`, `Teams`, `OBS`, `WhatsApp`, `Chrome`), live resolution/FPS, and call duration — **without ever requesting Camera or Microphone permissions**.
- Optional draggable, non-activating **Floating Stream Stats HUD** (`Off` / `While in Call` / `Always`) keeps live stream telemetry visible on screen without stealing window focus.

### 5. Punctual Single-Setting Rollback (`↺`), Hardware ID Presets & Anti-Reset Lock
- Every manual slider, mode selector, and stream parameter features a dedicated **Rollback (`↺`)** icon between the control icon and its value readout to restore **only that register** to factory `GET_DEF`.
- **Bind by Hardware ID (`VendorID:ProductID:Serial`)**, save unlimited named presets with **`★ Load at Start`**, and enable the **Anti-Reset Hardware Lock (`🔒`)** daemon to re-inject drifted registers every `2.5s`.

<div align="center">
<img src="docs/assets/menubar-and-preferences.png" alt="Menu Bar Popover and Preferences Hardware ID Lock" width="100%" />
</div>

---

## Installation

### Option A — Homebrew (Recommended)

Installs both **`/Applications/WebCam Controller.app`** and **`/opt/homebrew/bin/webcamctl`** (and clears Gatekeeper quarantine automatically):

```bash
brew install --cask SilverFeit/tap/macos-webcam-controller
```

To update to the latest version at any time:

```bash
brew upgrade --cask macos-webcam-controller
```

### Option B — Download Prebuilt `.dmg` / `.zip`

1. Go to [**GitHub Releases (`latest`)**](https://github.com/SilverFeit/MacOS-WebCam-Controller/releases/latest).
2. Download **`MacOS-WebCam-Controller-1.1.1.dmg`** *(or `MacOS-WebCam-Controller-1.1.1.app.zip`)*.
3. Open the `.dmg`, drag **WebCam Controller** into **Applications**, and launch it.

> [!NOTE]
> **First Launch via Manual Download (Gatekeeper):** Because open-source builds use ad-hoc signing rather than a paid Developer ID certificate, if you install manually via `.dmg`/`.zip` instead of Homebrew, right-click `WebCam Controller.app` → **`Open`** → **`Open`** (or run `xattr -dr com.apple.quarantine "/Applications/WebCam Controller.app"`). To add `webcamctl` to your `PATH` on manual installs:
> ```bash
> ln -sf "/Applications/WebCam Controller.app/Contents/MacOS/webcamctl" /opt/homebrew/bin/webcamctl
> ```

### Option C — Build from Source

Requires macOS 14+ on Apple Silicon with Xcode or Xcode Command Line Tools (`swift 6.0+`):

```bash
git clone https://github.com/SilverFeit/MacOS-WebCam-Controller.git
cd MacOS-WebCam-Controller

# Run unit + live USB UVC hardware test suite
swift run UVCCoreTests

# Build Release .app + webcamctl + .dmg + .app.zip + SHA256SUMS.txt
./Scripts/package_release.sh
```

---

## Command-Line Interface (`webcamctl`)

`webcamctl` shares presets and lock state with the Menu Bar app and syncs live register changes immediately to the open UI. Every subcommand also supports `--camera <id|index|name>` and `--json`:

```bash
# List connected USB UVC cameras, firmware & active stream state
webcamctl list

# Inspect UVC units, Extension Unit GUIDs, control ranges & video modes (add --raw for USB hex dump)
webcamctl describe
webcamctl describe --raw

# Read all controls or specific aliases
webcamctl get
webcamctl get shutter kelvin brightness zoom stream

# Set physical hardware registers (supports 1/60s shutter fractions & relative +/- deltas)
webcamctl set shutter=1/60 gain=40 kelvin=4500 brightness=+5 anti_flicker=60hz

# Negotiate hardware resolution, frame rate & codec
webcamctl stream 2k 30 mjpeg
webcamctl stream 1080p 60

# Reset individual controls or all registers to factory GET_DEF
webcamctl reset brightness kelvin
webcamctl reset all

# Manage per-camera presets & Anti-Reset Hardware Lock
webcamctl preset list
webcamctl preset save "Studio Daylight" --load-at-start
webcamctl preset apply "Studio Daylight"
webcamctl lock on

# Zero-permission active call inspection & GitHub update check
webcamctl who
webcamctl sessions
webcamctl check-update
```

---

## How Direct USB Hardware Control Works

<div align="center">
<img src="docs/assets/usb-architecture.svg" alt="USB UVC VideoStreaming vs Endpoint 0 VideoControl Architecture" width="100%" />
</div>

USB Video Class (UVC) cameras split communication into two independent logical interfaces inside the same physical USB cable:

1. **Video Streaming Interface (`bInterfaceSubClass = 0x02`):** High-bandwidth pipe owned by macOS `UVCAssistant` / `AVFoundation`, delivering untouched video frames straight to Zoom, OBS, Teams, or your browser.
2. **Video Control Interface (`bInterfaceSubClass = 0x01` — Endpoint 0):** Lightweight control channel where **MacOS WebCam Controller** and **`webcamctl`** send non-exclusive `IOUSBInterfaceInterface` / `IOUSBDeviceInterface` control transfers (`GET_INFO`, `GET_MIN`, `GET_MAX`, `GET_RES`, `GET_DEF`, `GET_CUR`, `SET_CUR`) directly to the Camera Terminal (`CT`) and Processing Unit (`PU`).

---

## Requirements & Compatibility

- **Mac Architecture:** Apple Silicon (`arm64` — M1, M2, M3, M4, and newer).
- **Operating System:** macOS 14.0 Sonoma or later *(tested through **macOS 27.0.1**)*.
- **Supported Cameras:** External UVC-compliant USB webcams (Logitech, Elgato, Creative, Razer, Insta360, Anker, Obsbot, Sony/Canon/Lumix UVC interfaces, and generic USB 2.0/3.0 UVC webcams).
- **Not Supported:** Built-in MacBook / iMac FaceTime HD cameras (connected to Apple's proprietary internal ISP rather than USB UVC).

---

## Privacy & Security by Design

- **Zero Camera Permission:** Never opens an `AVCaptureSession` and never reads a single pixel of your video feed.
- **Zero Microphone Permission:** Passive call attribution inspects only macOS `CoreMediaIO` / `CoreAudio` process metadata — never audio samples.
- **Zero Telemetry:** Presets and call history stay 100% local in `UserDefaults` (`com.webcamcontroller.uvc`) and bounded local logs (`~/Library/Logs/WebCamController.log`). The only network request is a lightweight GitHub Releases version check (`api.github.com/repos/SilverFeit/MacOS-WebCam-Controller/releases/latest`), which can be toggled off anytime in **Preferences**.
- **Zero Kernel / System Extensions:** Pure user-space `IOKit` USB control transfers.

Read the [**Full User Guide (`docs/USER_GUIDE.md`)**](docs/USER_GUIDE.md) and [**Changelog (`CHANGELOG.md`)**](CHANGELOG.md) for complete details.

---

## Project Structure

```text
MacOS-WebCam-Controller/
├── Package.swift                        # SwiftPM manifest (CUVCHardware + UVCCore + App + webcamctl + Tests)
├── VERSION                              # Single source of truth for release & bundle version
├── Casks/macos-webcam-controller.rb     # Homebrew Cask definition (synced with SilverFeit/homebrew-tap)
├── Sources/
│   ├── CUVCHardware/                    # C11 IOKit / IOUSBLib UVC Endpoint 0, XU & raw descriptor engine
│   ├── UVCCore/                         # Swift 6 device introspection, CLI bridge, call monitor & updater
│   ├── WebcamControllerApp/             # Native AppKit NSStatusItem + SwiftUI Menu Bar, Panel & Stream HUD
│   └── webcamctl/                       # Command-line interface for scripting, Raycast, Shortcuts & CI
├── Tests/UVCCoreTests/                  # Unit + live USB hardware register read/write verification suite
├── Scripts/                             # App + CLI bundle builder, Retina .icns generator & DMG packager
└── docs/                                # User Guide, Retina UI screenshots & vector USB architecture diagram
```

---

## License

Released under the [MIT License](LICENSE). Copyright © 2026 [SilverFeit](https://github.com/SilverFeit).

---

<div align="center">

**Topics & Hashtags**

`#macOS` `#WebcamController` `#Homebrew` `#CLI` `#UVC` `#USBCamera` `#WebcamSettings` `#MenuBarApp` `#AppleSilicon` `#SwiftUI` `#IOKit` `#HardwareControl` `#ManualExposure` `#WhiteBalance` `#OBSStudio` `#Zoom` `#VideoConferencing` `#StreamingTools` `#MacUtilities` `#OpenSource`

</div>
