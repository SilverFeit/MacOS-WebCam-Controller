<div align="center">

<img src="assets/app-icon.png" alt="MacOS WebCam Controller Icon" width="88" height="88" />

# MacOS WebCam Controller — User Guide

**Version 1.0 · Direct USB UVC Hardware Control for Apple Silicon Macs**

</div>

MacOS WebCam Controller changes the physical hardware settings of an external USB webcam directly from the macOS menu bar and from a standalone window titled **Webcam Settings Panel**. The app does not display a live preview and does not record microphone audio. Adjust a control here, and the webcam applies that register directly inside its sensor/ISP for whatever app is already displaying your camera picture.

<p align="center">
  <img src="assets/panel-basic-advanced.png" alt="Basic and Advanced Tabs" width="100%" />
</p>

## Requirements

- An Apple Silicon Mac. Certified compatibility is **Apple Silicon only** (arm64). This release does not support Intel Macs.
- macOS 14 or later.
- Tested on **macOS 27.0.1 (Build 26A434)**.
- An external USB webcam that exposes standard USB video controls. The built-in Mac camera is not controlled by this app.
- Each slider, mode, and switch is limited to what that specific camera implements. Unsupported items appear disabled or as **N/A**.

## Install

1. Download `MacOS-WebCam-Controller-1.0.dmg` from the v1.0 release.
2. Open the disk image. It contains **WebCam Controller** and a shortcut to **Applications**.
3. Drag **WebCam Controller** onto **Applications**.
4. Eject the disk image.

You can instead download `MacOS-WebCam-Controller-1.0.app.zip`, unzip it, and move **WebCam Controller.app** into **Applications**.

## First launch and permissions

Open **WebCam Controller** from the Applications folder. The app runs as a menu-bar item (the webcam icon). It does not add a lasting Dock icon until the settings window is open.

This copy is ad-hoc signed, so Gatekeeper may block the first open:

- Control-click the app and choose **Open**, then confirm **Open**.
- Or go to **System Settings → Privacy & Security** and choose **Open Anyway** for WebCam Controller.

**Camera and Microphone:** the app does not request either permission. It never opens a capture session. You should not see a Camera or Microphone prompt from this app. If a prompt appears, it is from the other program that is displaying the camera, not from WebCam Controller.

**Login item:** after the app is in Applications, you can enable **Launch WebCam Controller automatically at macOS Login** on the Preferences tab. macOS may ask you to approve that login item under **System Settings → General → Login Items & Extensions**. If registration fails, the error text is shown under the checkbox.

## Menu bar

Left-click the webcam icon to open a panel about 414 points wide.

| Control | What it does |
| --- | --- |
| Camera name or picker | Shows the connected webcam. With two or more cameras, a menu lists each product name and its USB vendor/product id. Choosing one makes that camera the target of every control. |
| Lock | Turns **hardware lock** on or off. The icon is a closed lock while lock is on. |
| Circular arrow | Rescans USB webcams and reads their current values. |
| **Panel** | Opens **Webcam Settings Panel** on the **Basic** tab. |
| **Advanced…** | Opens **Webcam Settings Panel** on the **Advanced** tab. |
| Gear | Opens **Webcam Settings Panel** on the **Preferences** tab. |
| Basic controls | The same exposure, image, and white-balance controls as the Basic tab, in a shorter layout. |
| Preset menu | **Camera Default** restores the camera’s own defaults. Saved presets for this camera are listed underneath. A star marks the preset set to load at start. Choosing an entry applies it immediately. |
| **Defaults** | Restores hardware defaults and selects **Camera Default**. |
| Power icon | Quits the app. |

Clicking outside the popover closes it. Right-clicking the menu-bar icon opens the settings window directly on **Advanced**.

If no compatible webcam is connected, the popover says **No USB UVC Camera**, explains that you need to plug one in, and offers **Rescan USB** and **Quit**.

By default, unsupported sliders are hidden in this popover (**Hide unsupported hardware sliders inside Menu Bar quick popover** is on). The full window still shows those controls.

## Webcam Settings Panel

The window title is **Webcam Settings Panel**. It can be resized (minimum about 456×620). While it is open, the app appears in the Dock like a normal application. Closing the window hides the Dock icon again and leaves only the menu-bar item. Opening the app again from the Finder while it is already running brings this window forward.

The header has:

- A camera menu, labeled with the product name and USB id, or the text **No USB UVC Webcam Connected**.
- A pin button. When filled, the window stays above other windows. The same choice is on the Preferences tab as **Keep 'Webcam Settings Panel' floating above other windows**.
- A rescan button.

Under that, a segmented control switches **Basic**, **Advanced**, and **Preferences**.

A status line at the bottom shows a short message (green when a camera is selected, orange when none is). **Locked** appears there while hardware lock is on.

If nothing is connected, the window asks you to connect an external USB webcam and offers **Scan USB Devices**.

### Basic

**Exposure**

- **Auto-Exposure Mode:** Manual, Auto, Shutter Priority, and Aperture Priority. Only modes the camera reports are enabled. Shutter Priority and Manual allow the exposure-time slider. Aperture Priority and Manual allow the aperture slider on the Advanced tab when the camera has one.
- **Exposure Time** and **Gain** sliders.

**Image**

- **Brightness**, **Contrast**, **Hue**, **Saturation**, **Sharpness**, and **Gamma**.
- If the camera is currently applying contrast or hue automatically, that slider is locked until automatic mode is no longer active. There is no separate on/off switch for those two automatic modes in this window; presets can still store the camera’s automatic state.

**White Balance Temperature**

- An **Auto** checkbox. While Auto is on, the temperature slider is locked.
- The temperature slider shows the value in kelvin (for example `4500K`) when the camera supports it.

Every active slider has a rollback arrow. The arrow is highlighted when the value is not the camera default. The numeric readout is accent-colored when it differs from the default, and **N/A** when the camera does not support that control.

### Advanced

**Video Resolution & Frame Rate** (when the camera describes its video modes)

- **Format**, if the camera offers more than one.
- **Resolution** menu, highest resolutions first.
- **FPS** choices that the selected resolution actually supports. Unavailable rates stay disabled.
- A compatibility line lists the frame rates for the current resolution, and a status line reports the live or committed USB mode.
- Rollback arrows restore the camera’s default format, resolution, or frame rate.
- If another program already has the camera stream open, the app still records the format you chose. That choice is committed on the camera when the stream can be updated, and otherwise staged until the program using the camera starts the stream again. The status line states which of those happened.

**Power Line Frequency (anti-flicker)**

- Disabled, 50 Hz, 60 Hz, and Auto, limited to the range the camera accepts.

**Backlight Compensation**

- Off and On. If the camera supports more than a single step, a **Level** slider appears.

**Low Light Compensation (AE Priority)**

- **Off (Constant FPS)** or **On (Auto Low-Light)**.

**Focus**

- **Auto** checkbox and a manual focus slider. Auto locks the slider.

**Movement and optics**

- **Zoom** uses the camera’s optical zoom when present, otherwise its digital zoom control when that is the one the camera provides.
- **Pan** and **Tilt**, shown in degrees when the camera reports absolute position.
- **Aperture**, only if the camera supports it. It is locked unless the exposure mode allows manual aperture.
- **Roll**, only if supported.
- **Hardware Privacy Shutter**, only if supported. The label reads **Closed** or **Open**.
- **Progressive Scan**, only if supported. The readout is **Prog** or **Interl**.

### Preferences

**Target USB Camera (Configured by Hardware ID)** shows, for the selected camera:

- Device name
- USB vendor and product id
- USB location and serial number (or **N/A**)
- Descriptor summary (version and unit ids)
- **Configured ID** (**Auto** until a camera has been stored)

Buttons:

- **Bind Active Camera ID** stores this camera as the one to select when it is present.
- **Rescan USB Bus** looks for webcams again.
- **Refresh Registers** reads the live values from the selected camera.

**Hardware Control & Menu Bar Preferences**

- **Lock Hardware Values (Anti-Reset Daemon).** Off by default. About every 2.5 seconds the app compares the selected camera with the values you set and writes back any that drifted. The status line reports how many values were re-applied. The same switch is the lock button in the menu bar.
- **Automatically apply 'Load at Start' preset when USB camera connects.** On by default. When a webcam is detected, the preset marked **Load at Start** for that camera is applied once for that connection.
- **Hide unsupported hardware sliders inside Menu Bar quick popover.** On by default.
- **Keep 'Webcam Settings Panel' floating above other windows.** Off by default.
- **Launch WebCam Controller automatically at macOS Login.** Uses the system login-item setting for this app. See First launch above.

**Restore Hardware Defaults** writes the camera’s default for every supported control and selects **Camera Default**.

**Quit WebCam Controller** exits the app.

### Manage Settings

Shown under Basic and Advanced, not on Preferences.

- **Save Current Settings** asks for a name (the field suggests names such as Daylight, Studio, or Night, and defaults to `Preset N`). **Save** stores the current controls for this camera. Saving the same name updates that preset.
- **Delete Saved Settings** removes the preset selected in the menu. **Camera Default** cannot be deleted.
- The preset menu applies **Camera Default** or a saved preset as soon as you choose it.
- **Load at Start** toggles that flag on the selected preset. Only one preset per camera is marked. The menu shows a star beside that preset. Choosing **Load at Start** while **Camera Default** is selected clears the startup preset.

Presets are stored on this Mac for each camera identity and are not synced by the app.

## Hardware lock

Turn the lock on after you have the picture the way you want it. The app remembers that snapshot for the selected camera and, while the lock stays on, puts those values back if they change. Quit, or turn the lock off, to stop the reapply cycle. The preference is remembered the next time you launch the app.

## Multiple cameras

The app watches for webcams being plugged in or removed and refreshes the list. It can track up to 16 USB video devices at once. Use the camera menu to pick the active one. **Bind Active Camera ID** keeps a specific camera preferred across launches. Presets and **Load at Start** belong to the camera they were saved for, not to every camera on the bus.

## Limitations

- Certified compatibility is Apple Silicon only. Do not expect this build to run on Intel Macs.
- macOS 14 or later is required. The copy used for this release was tested on macOS 27.0.1 (Build 26A434).
- Built-in Mac cameras are not supported.
- A control is only as capable as the webcam. Ranges, steps, and which modes exist all come from the device.
- There is no preview inside the app.
- The app does not request Camera or Microphone access, and it does not replace the program that is displaying the camera.
- If a video program already owns the camera stream, a resolution or frame-rate change may be staged until that program opens the stream again.
- Contrast-auto and hue-auto do not have their own checkboxes. A slider stays locked while the camera reports that automatic mode as on.
- Login-item registration depends on macOS accepting this app. Keep the app in Applications before enabling it. An ad-hoc signature can cause that request to fail; the Preferences tab shows the error when it does.
- The release app is ad-hoc signed. macOS will warn on first launch until you choose Open.
