#ifndef CUVC_HARDWARE_H
#define CUVC_HARDWARE_H

#include <stdint.h>
#include <stdbool.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

#ifdef __cplusplus
extern "C" {
#endif

/// UVC Class-Specific Request Codes (UVC 1.5 Spec Table A-8)
typedef enum {
    CUVC_REQ_SET_CUR  = 0x01,
    CUVC_REQ_GET_CUR  = 0x81,
    CUVC_REQ_GET_MIN  = 0x82,
    CUVC_REQ_GET_MAX  = 0x83,
    CUVC_REQ_GET_RES  = 0x84,
    CUVC_REQ_GET_LEN  = 0x85,
    CUVC_REQ_GET_INFO = 0x86,
    CUVC_REQ_GET_DEF  = 0x87
} CUVCRequestCode;

/// UVC GET_INFO capability bits (UVC 1.5 Spec Section 4.1.2)
typedef enum {
    CUVC_INFO_SUPPORTS_GET          = (1 << 0),
    CUVC_INFO_SUPPORTS_SET          = (1 << 1),
    CUVC_INFO_DISABLED_DUE_TO_AUTO  = (1 << 2),
    CUVC_INFO_AUTOUPDATE_CONTROL    = (1 << 3),
    CUVC_INFO_ASYNCHRONOUS_CONTROL  = (1 << 4)
} CUVCInfoBits;

/// Camera Terminal Control Selectors (UVC 1.5 Spec Table A-9)
typedef enum {
    CUVC_CT_SCANNING_MODE_CONTROL          = 0x01,
    CUVC_CT_AE_MODE_CONTROL                = 0x02,
    CUVC_CT_AE_PRIORITY_CONTROL            = 0x03,
    CUVC_CT_EXPOSURE_TIME_ABSOLUTE_CONTROL = 0x04,
    CUVC_CT_EXPOSURE_TIME_RELATIVE_CONTROL = 0x05,
    CUVC_CT_FOCUS_ABSOLUTE_CONTROL         = 0x06,
    CUVC_CT_FOCUS_RELATIVE_CONTROL         = 0x07,
    CUVC_CT_FOCUS_AUTO_CONTROL             = 0x08,
    CUVC_CT_IRIS_ABSOLUTE_CONTROL          = 0x09,
    CUVC_CT_IRIS_RELATIVE_CONTROL          = 0x0A,
    CUVC_CT_ZOOM_ABSOLUTE_CONTROL          = 0x0B,
    CUVC_CT_ZOOM_RELATIVE_CONTROL          = 0x0C,
    CUVC_CT_PANTILT_ABSOLUTE_CONTROL       = 0x0D,
    CUVC_CT_PANTILT_RELATIVE_CONTROL       = 0x0E,
    CUVC_CT_ROLL_ABSOLUTE_CONTROL          = 0x0F,
    CUVC_CT_ROLL_RELATIVE_CONTROL          = 0x10,
    CUVC_CT_PRIVACY_CONTROL                = 0x11,
    CUVC_CT_FOCUS_SIMPLE_CONTROL           = 0x12
} CUVCCameraTerminalSelector;

/// Processing Unit Control Selectors (UVC 1.5 Spec Table A-11)
typedef enum {
    CUVC_PU_BACKLIGHT_COMPENSATION_CONTROL         = 0x01,
    CUVC_PU_BRIGHTNESS_CONTROL                     = 0x02,
    CUVC_PU_CONTRAST_CONTROL                       = 0x03,
    CUVC_PU_GAIN_CONTROL                           = 0x04,
    CUVC_PU_POWER_LINE_FREQUENCY_CONTROL           = 0x05,
    CUVC_PU_HUE_CONTROL                            = 0x06,
    CUVC_PU_SATURATION_CONTROL                     = 0x07,
    CUVC_PU_SHARPNESS_CONTROL                      = 0x08,
    CUVC_PU_GAMMA_CONTROL                          = 0x09,
    CUVC_PU_WHITE_BALANCE_TEMPERATURE_CONTROL      = 0x0A,
    CUVC_PU_WHITE_BALANCE_TEMPERATURE_AUTO_CONTROL = 0x0B,
    CUVC_PU_WHITE_BALANCE_COMPONENT_CONTROL        = 0x0C,
    CUVC_PU_WHITE_BALANCE_COMPONENT_AUTO_CONTROL   = 0x0D,
    CUVC_PU_DIGITAL_MULTIPLIER_CONTROL             = 0x0E,
    CUVC_PU_DIGITAL_MULTIPLIER_LIMIT_CONTROL       = 0x0F,
    CUVC_PU_HUE_AUTO_CONTROL                       = 0x10,
    CUVC_PU_ANALOG_VIDEO_STANDARD_CONTROL          = 0x11,
    CUVC_PU_ANALOG_LOCK_STATUS_CONTROL             = 0x12,
    CUVC_PU_CONTRAST_AUTO_CONTROL                  = 0x13
} CUVCProcessingUnitSelector;

/// UVC VideoStreaming Codec Types (UVC 1.5 Spec Payload Formats)
typedef enum {
    CUVC_VS_CODEC_UNCOMPRESSED = 1,
    CUVC_VS_CODEC_MJPEG        = 2,
    CUVC_VS_CODEC_FRAME_BASED  = 3
} CUVCStreamCodec;

#define CUVC_MAX_FPS_INTERVALS 16
#define CUVC_MAX_STREAM_MODES  64

/// Discovered USB UVC VideoStreaming Frame/Resolution Mode + Supported Frame Intervals
typedef struct {
    uint8_t  videoStreamingInterfaceNumber;
    uint8_t  formatIndex;
    uint8_t  frameIndex;
    uint8_t  codec; // CUVCStreamCodec
    uint16_t width;
    uint16_t height;
    uint32_t defaultFrameInterval100ns;
    uint8_t  intervalCount;
    uint32_t frameIntervals100ns[CUVC_MAX_FPS_INTERVALS];
} CUVCStreamMode;

/// Live Negotiated UVC VideoStreaming Probe/Commit State
typedef struct {
    bool     isValid;
    uint8_t  videoStreamingInterfaceNumber;
    uint8_t  alternateSetting;
    uint8_t  formatIndex;
    uint8_t  frameIndex;
    uint32_t frameInterval100ns;
    uint32_t maxVideoFrameSize;
    uint32_t maxPayloadTransferSize;
} CUVCActiveStreamState;

/// Discovered USB UVC camera metadata
typedef struct {
    uint16_t vendorId;
    uint16_t productId;
    uint32_t locationId;
    uint16_t uvcVersionBCD;
    uint8_t  videoControlInterfaceNumber;
    int16_t  cameraTerminalId;
    int16_t  processingUnitId;
    uint32_t cameraTerminalControlsBitmap;
    uint32_t processingUnitControlsBitmap;
    char     productName[256];
    char     vendorName[256];
    char     serialNumber[128];
} CUVCDeviceInfo;

/// Opaque handle to an open UVC control channel (Endpoint 0, non-exclusive)
typedef struct CUVCDeviceHandle CUVCDeviceHandle;

/// Callback invoked on main run loop when USB devices are attached or detached
typedef void (*CUVCHotplugCallback)(void *context);

/// Opaque handle to USB hot-plug watcher
typedef struct CUVCHotplugWatcher CUVCHotplugWatcher;

/// Enumerate all connected UVC-compliant USB cameras directly via IOKit.
int cuvc_enumerate_devices(CUVCDeviceInfo *outDevices, int maxDevices);

/// Open a non-exclusive Endpoint 0 control handle to the UVC camera at `locationId`
/// (with fallback to `vendorId` + `productId` if `locationId == 0`).
CUVCDeviceHandle *cuvc_open_device(uint32_t locationId, uint16_t vendorId, uint16_t productId);

/// Retrieve metadata for an open handle.
CUVCDeviceInfo cuvc_get_device_info(const CUVCDeviceHandle *handle);

/// Close and release IOKit interfaces for `handle`.
void cuvc_close_device(CUVCDeviceHandle *handle);

/// Enumerate all hardware UVC VideoStreaming resolutions and compatible FPS intervals
/// directly from the USB Configuration Descriptor (`SC_VIDEOSTREAMING = 0x02`).
int cuvc_enumerate_stream_modes(
    CUVCDeviceHandle *handle,
    CUVCStreamMode *outModes,
    int maxModes
);

/// Read the currently active UVC VideoStreaming state (`VS_COMMIT_CONTROL` / `VS_PROBE_CONTROL` `GET_CUR`).
bool cuvc_get_active_stream_state(
    CUVCDeviceHandle *handle,
    uint8_t vsInterfaceNumber,
    CUVCActiveStreamState *outState
);

/// Negotiate (`VS_PROBE_CONTROL`) and optionally commit (`VS_COMMIT_CONTROL`) a format, frame,
/// and 100ns frame interval on the UVC VideoStreaming interface over Endpoint 0.
bool cuvc_negotiate_stream_state(
    CUVCDeviceHandle *handle,
    uint8_t vsInterfaceNumber,
    uint8_t formatIndex,
    uint8_t frameIndex,
    uint32_t frameInterval100ns,
    bool commitToStream,
    CUVCActiveStreamState *outNegotiated
);

/// Perform a raw UVC GET request over Endpoint 0 without seizing the USB interface.
bool cuvc_get_control_bytes(
    CUVCDeviceHandle *handle,
    uint8_t requestCode,
    uint8_t unitId,
    uint8_t selector,
    void *outBuffer,
    uint16_t length,
    uint16_t *outBytesTransferred
);

/// Perform a raw UVC `SET_CUR` request over Endpoint 0 without seizing the USB interface.
bool cuvc_set_control_bytes(
    CUVCDeviceHandle *handle,
    uint8_t unitId,
    uint8_t selector,
    const void *inBuffer,
    uint16_t length
);

/// Convenience typed getters/setters (handles USB little-endian <-> host conversion automatically)
bool cuvc_get_info(CUVCDeviceHandle *handle, uint8_t unitId, uint8_t selector, uint8_t *outInfo);

bool cuvc_get_int(
    CUVCDeviceHandle *handle,
    uint8_t requestCode,
    uint8_t unitId,
    uint8_t selector,
    uint8_t byteLength,
    bool isSigned,
    int64_t *outValue
);

bool cuvc_set_int(
    CUVCDeviceHandle *handle,
    uint8_t unitId,
    uint8_t selector,
    uint8_t byteLength,
    bool isSigned,
    int64_t value
);

/// Pan/Tilt 8-byte signed 32-bit pair (in arcseconds per UVC spec)
bool cuvc_get_pantilt(
    CUVCDeviceHandle *handle,
    uint8_t requestCode,
    uint8_t unitId,
    int32_t *outPan,
    int32_t *outTilt
);

bool cuvc_set_pantilt(
    CUVCDeviceHandle *handle,
    uint8_t unitId,
    int32_t pan,
    int32_t tilt
);

/// Start watching USB device plug/unplug events on the main CFRunLoop.
CUVCHotplugWatcher *cuvc_start_hotplug_watcher(CUVCHotplugCallback callback, void *context);

/// Stop and release a USB hot-plug watcher.
void cuvc_stop_hotplug_watcher(CUVCHotplugWatcher *watcher);

#ifdef __cplusplus
}
#endif

#endif /* CUVC_HARDWARE_H */
