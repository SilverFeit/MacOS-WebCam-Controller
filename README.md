# MacOS WebCam Controller

MacOS WebCam Controller is a menu-bar app for Apple Silicon Macs. It adjusts the hardware controls of an external USB webcam: exposure, image settings, white balance, focus, zoom, pan, tilt, and the other controls that camera actually offers. A webcam icon stays in the menu bar. From there you can change the common settings immediately, or open the **Webcam Settings Panel** window for the full set of controls.

The app does not show a camera preview and does not record audio. It writes settings to the webcam itself, so the picture you already see in another program can update while that program keeps using the camera.

Version **1.0**.

## Requirements

- Apple Silicon Mac (arm64)
- macOS 14 or later
- Tested on **macOS 27.0.1 (Build 26A434)**
- **Certified compatibility: Apple Silicon only**
- An external USB webcam. Built-in Mac cameras are not supported. Controls that the camera does not implement are shown as unavailable.

## Install

1. Open the [v1.0 release](https://github.com/SilverFeit/MacOS-WebCam-Controller/releases/tag/v1.0).
2. Download `MacOS-WebCam-Controller-1.0.dmg`.
3. Open the disk image.
4. Drag **WebCam Controller** onto the **Applications** folder.

A zip of the app, `MacOS-WebCam-Controller-1.0.app.zip`, is on the same release if you prefer to unzip it and move **WebCam Controller.app** into Applications yourself.

## First launch

The app is a menu-bar utility. After it starts, look for the webcam icon in the menu bar. It does not stay in the Dock until you open the settings window.

This build is ad-hoc signed. The first time you open it, macOS may report that it cannot verify the developer. If that happens:

1. Move the app to **Applications** if it is not already there.
2. Control-click **WebCam Controller** and choose **Open**, then **Open** again.
3. If macOS still blocks it, open **System Settings → Privacy & Security** and allow the app.

The app does not request Camera or Microphone permission. It does not capture video or audio. No camera or microphone prompt is expected.

## How to use

- **Left-click** the menu-bar icon to open the quick controls: camera name (or a picker when more than one USB webcam is connected), lock, rescan, **Panel**, **Advanced…**, image and exposure sliders, a preset menu, **Defaults**, and Quit.
- **Right-click** the menu-bar icon to open the **Webcam Settings Panel** on the **Advanced** tab.
- **Panel** opens that window on **Basic**. The gear button opens it on **Preferences**.
- **Basic** covers auto-exposure mode, exposure time, gain, brightness, contrast, hue, saturation, sharpness, gamma, and white balance.
- **Advanced** covers power-line frequency (anti-flicker), backlight compensation, low-light compensation, focus, zoom, pan, and tilt, plus format, resolution, and frame rate when the camera reports them. Aperture, roll, a hardware privacy shutter, and progressive scan appear only when that camera supports them.
- **Preferences** shows the camera’s USB identity, lets you bind that camera, rescan, turn on hardware lock, load a startup preset, hide unsupported sliders in the menu bar, keep the panel above other windows, and launch the app at login.
- **Manage Settings** (under Basic and Advanced) saves, loads, and deletes named presets for the selected camera. **Load at Start** marks one preset to apply when that camera connects.
- The lock keeps reapplying your current values if they change. It is off until you turn it on.
- Closing the settings window returns the app to the menu bar only.

A step-by-step guide is in [docs/USER_GUIDE.md](docs/USER_GUIDE.md).

## Certified compatibility

Certified compatibility is **Apple Silicon only**. This 1.0 build is an arm64 app. Intel Macs are not a supported configuration.
