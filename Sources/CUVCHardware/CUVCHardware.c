#include "CUVCHardware.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <libkern/OSByteOrder.h>
#include <IOKit/IOMessage.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

#define UVC_CS_INTERFACE       0x24
#define UVC_VC_HEADER          0x01
#define UVC_VC_INPUT_TERMINAL  0x02
#define UVC_VC_OUTPUT_TERMINAL 0x03
#define UVC_VC_SELECTOR_UNIT   0x04
#define UVC_VC_PROCESSING_UNIT 0x05
#define UVC_VC_EXTENSION_UNIT  0x06

#define UVC_VS_FORMAT_UNCOMPRESSED 0x04
#define UVC_VS_FRAME_UNCOMPRESSED  0x05
#define UVC_VS_FORMAT_MJPEG        0x06
#define UVC_VS_FRAME_MJPEG         0x07
#define UVC_VS_FORMAT_FRAME_BASED  0x10
#define UVC_VS_FRAME_FRAME_BASED   0x11

#define UVC_VS_PROBE_CONTROL       0x01
#define UVC_VS_COMMIT_CONTROL      0x02

#define UVC_ITT_CAMERA         0x0201

struct CUVCDeviceHandle {
    CUVCDeviceInfo info;
    IOUSBDeviceInterface **deviceInterface;
    IOUSBInterfaceInterface220 **controlInterface;
    int32_t lastError;
};

struct CUVCHotplugWatcher {
    IONotificationPortRef notifyPort;
    io_iterator_t addedIter;
    io_iterator_t removedIter;
    CUVCHotplugCallback callback;
    void *context;
};

static uint16_t read_le16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t read_le32(const uint8_t *p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static void write_le16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
}

static void write_le32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

static bool read_cfstring_property(io_service_t service, CFStringRef key, char *outBuf, size_t bufSize) {
    if (!outBuf || bufSize == 0) return false;
    CFTypeRef prop = IORegistryEntrySearchCFProperty(service, kIOUSBPlane, key, kCFAllocatorDefault, 0);
    if (!prop) {
        prop = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    }
    if (!prop) return false;

    bool ok = false;
    if (CFGetTypeID(prop) == CFStringGetTypeID()) {
        ok = CFStringGetCString((CFStringRef)prop, outBuf, (CFIndex)bufSize, kCFStringEncodingUTF8);
    }
    CFRelease(prop);
    return ok && outBuf[0] != '\0';
}

static bool read_cfnumber_int64(io_service_t service, CFStringRef key, int64_t *outVal) {
    CFTypeRef prop = IORegistryEntrySearchCFProperty(service, kIOUSBPlane, key, kCFAllocatorDefault, 0);
    if (!prop) {
        prop = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    }
    if (!prop) return false;

    bool ok = false;
    if (CFGetTypeID(prop) == CFNumberGetTypeID()) {
        ok = CFNumberGetValue((CFNumberRef)prop, kCFNumberSInt64Type, outVal);
    }
    CFRelease(prop);
    return ok;
}

static void parse_uvc_subdescriptor(const uint8_t *bytes, size_t len, CUVCDeviceInfo *info) {
    if (len < 4 || bytes[1] != UVC_CS_INTERFACE) return;
    uint8_t subType = bytes[2];

    if (subType == UVC_VC_HEADER && len >= 7) {
        info->uvcVersionBCD = read_le16(bytes + 3);
    } else if (subType == UVC_VC_INPUT_TERMINAL && len >= 8) {
        uint8_t termId = bytes[3];
        uint16_t termType = read_le16(bytes + 4);
        if (termType == UVC_ITT_CAMERA || info->cameraTerminalId < 0) {
            info->cameraTerminalId = (int16_t)termId;
            if (termType == UVC_ITT_CAMERA && len >= 15) {
                uint8_t ctrlSize = bytes[14];
                uint32_t bitmap = 0;
                for (uint8_t i = 0; i < ctrlSize && i < 4 && (size_t)(15 + i) < len; i++) {
                    bitmap |= ((uint32_t)bytes[15 + i] << (i * 8));
                }
                info->cameraTerminalControlsBitmap = bitmap;
            }
        }
    } else if (subType == UVC_VC_PROCESSING_UNIT && len >= 8) {
        uint8_t unitId = bytes[3];
        uint8_t ctrlSize = bytes[7];
        if (info->processingUnitId < 0 || ctrlSize > 0) {
            info->processingUnitId = (int16_t)unitId;
            uint32_t bitmap = 0;
            for (uint8_t i = 0; i < ctrlSize && i < 4 && (size_t)(8 + i) < len; i++) {
                bitmap |= ((uint32_t)bytes[8 + i] << (i * 8));
            }
            if (bitmap != 0 || info->processingUnitControlsBitmap == 0) {
                info->processingUnitControlsBitmap = bitmap;
            }
        }
    } else if (subType == UVC_VC_EXTENSION_UNIT && len >= 24) {
        uint8_t unitId = bytes[3];
        uint8_t numControls = bytes[20];
        uint8_t numInputPins = bytes[21];
        size_t sizeIdx = (size_t)(22 + numInputPins);
        if (sizeIdx < len && info->extensionUnitCount < CUVC_MAX_EXTENSION_UNITS) {
            // Avoid duplicates if walked twice
            bool alreadyPresent = false;
            for (uint8_t e = 0; e < info->extensionUnitCount; e++) {
                if (info->extensionUnits[e].unitId == unitId) {
                    alreadyPresent = true;
                    break;
                }
            }
            if (!alreadyPresent) {
                uint8_t ctrlSize = bytes[sizeIdx];
                if (sizeIdx + 1 + ctrlSize <= len) {
                    CUVCExtensionUnitInfo *xu = &info->extensionUnits[info->extensionUnitCount++];
                    memset(xu, 0, sizeof(*xu));
                    xu->unitId = unitId;
                    xu->controlCount = numControls;
                    memcpy(xu->guidBytes, bytes + 4, 16);
                    uint64_t bitmap = 0;
                    for (uint8_t i = 0; i < ctrlSize && i < 8; i++) {
                        bitmap |= ((uint64_t)bytes[sizeIdx + 1 + i] << (i * 8));
                    }
                    xu->controlsBitmap = bitmap;
                }
            }
        }
    }
}

static bool inspect_uvc_service(
    io_service_t usbDeviceService,
    CUVCDeviceInfo *outInfo,
    IOUSBDeviceInterface ***outDevIntf,
    IOUSBInterfaceInterface220 ***outCtrlIntf
) {
    memset(outInfo, 0, sizeof(CUVCDeviceInfo));
    outInfo->cameraTerminalId = -1;
    outInfo->processingUnitId = -1;

    int64_t val = 0;
    if (read_cfnumber_int64(usbDeviceService, CFSTR(kUSBVendorID), &val)) {
        outInfo->vendorId = (uint16_t)(val & 0xFFFF);
    }
    if (read_cfnumber_int64(usbDeviceService, CFSTR(kUSBProductID), &val)) {
        outInfo->productId = (uint16_t)(val & 0xFFFF);
    }
    if (read_cfnumber_int64(usbDeviceService, CFSTR(kUSBDevicePropertyLocationID), &val)) {
        outInfo->locationId = (uint32_t)(val & 0xFFFFFFFFu);
    }
    if (read_cfnumber_int64(usbDeviceService, CFSTR("bcdDevice"), &val)) {
        outInfo->firmwareBCD = (uint16_t)(val & 0xFFFF);
    }

    if (!read_cfstring_property(usbDeviceService, CFSTR("USB Product Name"), outInfo->productName, sizeof(outInfo->productName)) &&
        !read_cfstring_property(usbDeviceService, CFSTR(kUSBProductString), outInfo->productName, sizeof(outInfo->productName))) {
        io_name_t entryName;
        if (IORegistryEntryGetName(usbDeviceService, entryName) == KERN_SUCCESS && entryName[0] != '\0') {
            snprintf(outInfo->productName, sizeof(outInfo->productName), "%s", entryName);
        } else {
            snprintf(outInfo->productName, sizeof(outInfo->productName), "USB Camera (0x%04x:0x%04x)", outInfo->vendorId, outInfo->productId);
        }
    }

    if (!read_cfstring_property(usbDeviceService, CFSTR("USB Vendor Name"), outInfo->vendorName, sizeof(outInfo->vendorName))) {
        read_cfstring_property(usbDeviceService, CFSTR(kUSBVendorString), outInfo->vendorName, sizeof(outInfo->vendorName));
    }

    if (!read_cfstring_property(usbDeviceService, CFSTR("USB Serial Number"), outInfo->serialNumber, sizeof(outInfo->serialNumber))) {
        read_cfstring_property(usbDeviceService, CFSTR(kUSBSerialNumberString), outInfo->serialNumber, sizeof(outInfo->serialNumber));
    }

    IOCFPlugInInterface **devPlugIn = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        usbDeviceService,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &devPlugIn,
        &score
    );
    if (kr != kIOReturnSuccess || !devPlugIn) {
        return false;
    }

    IOUSBDeviceInterface **devIntf = NULL;
    HRESULT hr = (*devPlugIn)->QueryInterface(
        devPlugIn,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
        (LPVOID *)&devIntf
    );
    IODestroyPlugInInterface(devPlugIn);
    if (hr != 0 || !devIntf) {
        return false;
    }
    if (outInfo->firmwareBCD == 0) {
        UInt16 relNum = 0;
        if ((*devIntf)->GetDeviceReleaseNumber(devIntf, &relNum) == kIOReturnSuccess) {
            outInfo->firmwareBCD = relNum;
        }
    }

    IOUSBFindInterfaceRequest req = {
        .bInterfaceClass = kUSBVideoInterfaceClass,
        .bInterfaceSubClass = kUSBVideoControlSubClass,
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting = kIOUSBFindInterfaceDontCare
    };

    io_iterator_t intfIter = 0;
    IOReturn rc = (*devIntf)->CreateInterfaceIterator(devIntf, &req, &intfIter);
    if (rc != kIOReturnSuccess || !intfIter) {
        (*devIntf)->Release(devIntf);
        return false;
    }

    io_service_t usbInterface = IOIteratorNext(intfIter);
    IOObjectRelease(intfIter);
    if (!usbInterface) {
        (*devIntf)->Release(devIntf);
        return false;
    }

    IOCFPlugInInterface **intfPlugIn = NULL;
    kr = IOCreatePlugInInterfaceForService(
        usbInterface,
        kIOUSBInterfaceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &intfPlugIn,
        &score
    );
    IOObjectRelease(usbInterface);
    if (kr != kIOReturnSuccess || !intfPlugIn) {
        (*devIntf)->Release(devIntf);
        return false;
    }

    IOUSBInterfaceInterface220 **ctrlIntf = NULL;
    hr = (*intfPlugIn)->QueryInterface(
        intfPlugIn,
        CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID220),
        (LPVOID *)&ctrlIntf
    );
    if (hr != 0 || !ctrlIntf) {
        hr = (*intfPlugIn)->QueryInterface(
            intfPlugIn,
            CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
            (LPVOID *)&ctrlIntf
        );
    }
    IODestroyPlugInInterface(intfPlugIn);
    if (hr != 0 || !ctrlIntf) {
        (*devIntf)->Release(devIntf);
        return false;
    }

    UInt8 intfNum = 0;
    (*ctrlIntf)->GetInterfaceNumber(ctrlIntf, &intfNum);
    outInfo->videoControlInterfaceNumber = intfNum;

    IOUSBDescriptorHeader *desc = NULL;
    while ((desc = (*ctrlIntf)->FindNextAssociatedDescriptor(ctrlIntf, desc, UVC_CS_INTERFACE)) != NULL) {
        const uint8_t *raw = (const uint8_t *)desc;
        uint8_t dLen = raw[0];
        if (dLen < 3) continue;
        parse_uvc_subdescriptor(raw, dLen, outInfo);

        if (raw[2] == UVC_VC_HEADER && dLen >= 7) {
            uint16_t totalLen = read_le16(raw + 5);
            if (totalLen > dLen && totalLen <= 4096) {
                size_t offset = dLen;
                while (offset + 3 <= totalLen) {
                    uint8_t subLen = raw[offset];
                    if (subLen < 3 || offset + subLen > totalLen) break;
                    parse_uvc_subdescriptor(raw + offset, subLen, outInfo);
                    offset += subLen;
                }
            }
        }
    }

    if (outInfo->cameraTerminalId < 0) {
        outInfo->cameraTerminalId = 1;
    }
    if (outInfo->processingUnitId < 0) {
        outInfo->processingUnitId = 2;
    }

    if (outDevIntf && outCtrlIntf) {
        *outDevIntf = devIntf;
        *outCtrlIntf = ctrlIntf;
    } else {
        (*ctrlIntf)->Release(ctrlIntf);
        (*devIntf)->Release(devIntf);
    }
    return true;
}

int cuvc_enumerate_devices(CUVCDeviceInfo *outDevices, int maxDevices) {
    if (!outDevices || maxDevices <= 0) return 0;

    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matching) return 0;

    io_iterator_t iter = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) != KERN_SUCCESS || !iter) {
        return 0;
    }

    int count = 0;
    io_service_t service = 0;
    while ((service = IOIteratorNext(iter)) != 0) {
        if (count < maxDevices) {
            CUVCDeviceInfo info;
            if (inspect_uvc_service(service, &info, NULL, NULL)) {
                outDevices[count++] = info;
            }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
    return count;
}

CUVCDeviceHandle *cuvc_open_device(uint32_t locationId, uint16_t vendorId, uint16_t productId) {
    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matching) return NULL;

    io_iterator_t iter = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) != KERN_SUCCESS || !iter) {
        return NULL;
    }

    CUVCDeviceHandle *foundHandle = NULL;
    io_service_t service = 0;

    while ((service = IOIteratorNext(iter)) != 0) {
        CUVCDeviceInfo info;
        IOUSBDeviceInterface **devIntf = NULL;
        IOUSBInterfaceInterface220 **ctrlIntf = NULL;

        if (inspect_uvc_service(service, &info, &devIntf, &ctrlIntf)) {
            bool matchesLocation = (locationId != 0 && info.locationId == locationId);
            bool matchesVidPid = (locationId == 0 && info.vendorId == vendorId && info.productId == productId);

            if (matchesLocation || matchesVidPid) {
                foundHandle = (CUVCDeviceHandle *)calloc(1, sizeof(CUVCDeviceHandle));
                if (foundHandle) {
                    foundHandle->info = info;
                    foundHandle->deviceInterface = devIntf;
                    foundHandle->controlInterface = ctrlIntf;
                } else {
                    (*ctrlIntf)->Release(ctrlIntf);
                    (*devIntf)->Release(devIntf);
                }
                IOObjectRelease(service);
                break;
            } else {
                (*ctrlIntf)->Release(ctrlIntf);
                (*devIntf)->Release(devIntf);
            }
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
    return foundHandle;
}

CUVCDeviceInfo cuvc_get_device_info(const CUVCDeviceHandle *handle) {
    CUVCDeviceInfo empty;
    memset(&empty, 0, sizeof(empty));
    if (!handle) return empty;
    return handle->info;
}

int32_t cuvc_get_last_error(const CUVCDeviceHandle *handle) {
    if (!handle) return -1;
    return handle->lastError;
}

bool cuvc_copy_config_descriptor(
    CUVCDeviceHandle *handle,
    uint8_t *outBuffer,
    uint32_t capacity,
    uint32_t *outLength
) {
    if (outLength) *outLength = 0;
    if (!handle || !handle->deviceInterface || !outBuffer || capacity == 0) return false;

    IOUSBConfigurationDescriptorPtr conf = NULL;
    IOReturn kr = (*handle->deviceInterface)->GetConfigurationDescriptorPtr(handle->deviceInterface, 0, &conf);
    handle->lastError = (int32_t)kr;
    if (kr != kIOReturnSuccess || !conf) {
        return false;
    }

    uint32_t totalLen = (uint32_t)OSSwapLittleToHostInt16(conf->wTotalLength);
    if (outLength) *outLength = totalLen;
    if (totalLen > capacity) {
        return false;
    }
    memcpy(outBuffer, conf, totalLen);
    return true;
}

void cuvc_close_device(CUVCDeviceHandle *handle) {
    if (!handle) return;
    if (handle->controlInterface) {
        (*handle->controlInterface)->Release(handle->controlInterface);
        handle->controlInterface = NULL;
    }
    if (handle->deviceInterface) {
        (*handle->deviceInterface)->Release(handle->deviceInterface);
        handle->deviceInterface = NULL;
    }
    free(handle);
}

// MARK: - UVC VideoStreaming Descriptor Introspection & VS_PROBE / VS_COMMIT

static void append_unique_interval(CUVCStreamMode *mode, uint32_t interval100ns) {
    if (!mode || interval100ns == 0 || mode->intervalCount >= CUVC_MAX_FPS_INTERVALS) return;
    for (uint8_t i = 0; i < mode->intervalCount; i++) {
        if (mode->frameIntervals100ns[i] == interval100ns) return;
    }
    mode->frameIntervals100ns[mode->intervalCount++] = interval100ns;
}

int cuvc_enumerate_stream_modes(
    CUVCDeviceHandle *handle,
    CUVCStreamMode *outModes,
    int maxModes
) {
    if (!handle || !handle->deviceInterface || !outModes || maxModes <= 0) return 0;

    UInt8 numConf = 0;
    if ((*handle->deviceInterface)->GetNumberOfConfigurations(handle->deviceInterface, &numConf) != kIOReturnSuccess) {
        return 0;
    }

    int modeCount = 0;

    for (UInt8 c = 0; c < numConf && modeCount < maxModes; c++) {
        IOUSBConfigurationDescriptorPtr conf = NULL;
        if ((*handle->deviceInterface)->GetConfigurationDescriptorPtr(handle->deviceInterface, c, &conf) != kIOReturnSuccess || !conf) {
            continue;
        }

        uint16_t totalLen = OSSwapLittleToHostInt16(conf->wTotalLength);
        const uint8_t *p = (const uint8_t *)conf;
        uint16_t off = 0;

        int curIntfClass = -1;
        int curIntfSub = -1;
        int curIntfNum = -1;
        int curAlt = -1;
        uint8_t curFormatIdx = 0;
        uint8_t curCodec = 0;

        while (off + 2 <= totalLen && modeCount < maxModes) {
            uint8_t dLen = p[off];
            uint8_t dType = p[off + 1];
            if (dLen < 2 || off + dLen > totalLen) break;

            if (dType == kUSBInterfaceDesc && dLen >= 9) {
                curIntfNum = p[off + 2];
                curAlt = p[off + 3];
                curIntfClass = p[off + 5];
                curIntfSub = p[off + 6];
            } else if (curIntfClass == kUSBVideoInterfaceClass &&
                       curIntfSub == 0x02 && // SC_VIDEOSTREAMING
                       curAlt == 0 &&
                       dType == UVC_CS_INTERFACE &&
                       dLen >= 4) {
                uint8_t subType = p[off + 2];

                if (subType == UVC_VS_FORMAT_UNCOMPRESSED) {
                    curFormatIdx = p[off + 3];
                    curCodec = CUVC_VS_CODEC_UNCOMPRESSED;
                } else if (subType == UVC_VS_FORMAT_MJPEG) {
                    curFormatIdx = p[off + 3];
                    curCodec = CUVC_VS_CODEC_MJPEG;
                } else if (subType == UVC_VS_FORMAT_FRAME_BASED) {
                    curFormatIdx = p[off + 3];
                    curCodec = CUVC_VS_CODEC_FRAME_BASED;
                } else if ((subType == UVC_VS_FRAME_UNCOMPRESSED ||
                            subType == UVC_VS_FRAME_MJPEG ||
                            subType == UVC_VS_FRAME_FRAME_BASED) &&
                           curCodec != 0 &&
                           dLen >= 26) {
                    CUVCStreamMode mode;
                    memset(&mode, 0, sizeof(mode));
                    mode.videoStreamingInterfaceNumber = (uint8_t)curIntfNum;
                    mode.formatIndex = curFormatIdx;
                    mode.frameIndex = p[off + 3];
                    mode.codec = curCodec;
                    mode.width = read_le16(p + off + 5);
                    mode.height = read_le16(p + off + 7);

                    uint8_t ivType = 0;
                    if (subType == UVC_VS_FRAME_FRAME_BASED) {
                        mode.defaultFrameInterval100ns = read_le32(p + off + 17);
                        ivType = p[off + 21];
                    } else {
                        mode.defaultFrameInterval100ns = read_le32(p + off + 21);
                        ivType = p[off + 25];
                    }

                    if (ivType > 0) {
                        for (uint8_t k = 0; k < ivType && (uint16_t)(26 + k * 4 + 4) <= dLen; k++) {
                            uint32_t iv = read_le32(p + off + 26 + k * 4);
                            append_unique_interval(&mode, iv);
                        }
                    } else if (dLen >= 38) {
                        // Continuous interval range [minInterval (max FPS) ... maxInterval (min FPS)]
                        uint32_t minIv = read_le32(p + off + 26);
                        uint32_t maxIv = read_le32(p + off + 30);
                        if (minIv > 0 && maxIv >= minIv) {
                            const uint32_t stdFps[] = {120, 60, 50, 30, 25, 24, 20, 15, 10, 5};
                            append_unique_interval(&mode, minIv);
                            for (size_t s = 0; s < sizeof(stdFps)/sizeof(stdFps[0]); s++) {
                                uint32_t cand = 10000000u / stdFps[s];
                                if (cand >= minIv && cand <= maxIv) {
                                    append_unique_interval(&mode, cand);
                                }
                            }
                            append_unique_interval(&mode, maxIv);
                        }
                    }

                    if (mode.intervalCount == 0 && mode.defaultFrameInterval100ns > 0) {
                        append_unique_interval(&mode, mode.defaultFrameInterval100ns);
                    }

                    if (mode.width > 0 && mode.height > 0 && mode.intervalCount > 0) {
                        outModes[modeCount++] = mode;
                    }
                }
            }
            off += dLen;
        }
    }

    return modeCount;
}

static bool vs_ep0_request(CUVCDeviceHandle *handle, IOUSBDevRequest *req) {
    if (!handle || !handle->deviceInterface) return false;

    // Try non-exclusive ControlRequest on the target VideoStreaming USB interface first
    // (works cleanly while UVCAssistant / call apps hold the streaming interface), then fallback to DeviceRequest.
    uint8_t targetIfc = (uint8_t)(req->wIndex & 0xFF);
    IOUSBFindInterfaceRequest findReq = {
        .bInterfaceClass = kUSBVideoInterfaceClass,
        .bInterfaceSubClass = 0x02, // SC_VIDEOSTREAMING
        .bInterfaceProtocol = kIOUSBFindInterfaceDontCare,
        .bAlternateSetting = kIOUSBFindInterfaceDontCare
    };
    io_iterator_t iter = 0;
    if ((*handle->deviceInterface)->CreateInterfaceIterator(handle->deviceInterface, &findReq, &iter) == kIOReturnSuccess && iter) {
        io_service_t svc = 0;
        while ((svc = IOIteratorNext(iter)) != 0) {
            int64_t ifcNum = -1;
            if (read_cfnumber_int64(svc, CFSTR("bInterfaceNumber"), &ifcNum) && (uint8_t)ifcNum == targetIfc) {
                IOCFPlugInInterface **plug = NULL;
                SInt32 score = 0;
                if (IOCreatePlugInInterfaceForService(svc, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plug, &score) == kIOReturnSuccess && plug) {
                    IOUSBInterfaceInterface **vsIntf = NULL;
                    HRESULT hr = (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID *)&vsIntf);
                    IODestroyPlugInInterface(plug);
                    if (hr == 0 && vsIntf) {
                        req->wLenDone = 0;
                        IOReturn ifcKr = (*vsIntf)->ControlRequest(vsIntf, 0, req);
                        (*vsIntf)->Release(vsIntf);
                        if (ifcKr == kIOReturnSuccess) {
                            handle->lastError = 0;
                            IOObjectRelease(svc);
                            IOObjectRelease(iter);
                            return true;
                        }
                    }
                }
                IOObjectRelease(svc);
                break;
            }
            IOObjectRelease(svc);
        }
        IOObjectRelease(iter);
    }

    req->wLenDone = 0;
    IOReturn kr = (*handle->deviceInterface)->DeviceRequest(handle->deviceInterface, req);
    handle->lastError = (int32_t)kr;
    return (kr == kIOReturnSuccess);
}

static uint16_t query_vs_probe_length(CUVCDeviceHandle *handle, uint8_t vsInterfaceNumber) {
    uint8_t lenBuf[2] = {0};
    IOUSBDevRequest req;
    memset(&req, 0, sizeof(req));
    req.bmRequestType = USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface);
    req.bRequest = CUVC_REQ_GET_LEN;
    req.wValue = (uint16_t)(UVC_VS_PROBE_CONTROL << 8);
    req.wIndex = (uint16_t)vsInterfaceNumber;
    req.wLength = 2;
    req.pData = lenBuf;

    if (vs_ep0_request(handle, &req) && req.wLenDone >= 1) {
        uint16_t reported = (req.wLenDone == 2) ? read_le16(lenBuf) : lenBuf[0];
        if (reported >= 26 && reported <= 48) {
            // Test if camera actually returns `reported` bytes on GET_CUR; some UVC 1.0 cameras report 48 in GET_LEN
            // while using 26-byte payload blocks.
            uint8_t testBuf[64] = {0};
            IOUSBDevRequest testReq;
            memset(&testReq, 0, sizeof(testReq));
            testReq.bmRequestType = USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface);
            testReq.bRequest = CUVC_REQ_GET_CUR;
            testReq.wValue = (uint16_t)(UVC_VS_PROBE_CONTROL << 8);
            testReq.wIndex = (uint16_t)vsInterfaceNumber;
            testReq.wLength = reported;
            testReq.pData = testBuf;
            if (vs_ep0_request(handle, &testReq) && testReq.wLenDone >= 26) {
                return (uint16_t)testReq.wLenDone;
            }
        }
    }
    return 26;
}

static uint8_t query_vs_alternate_setting(CUVCDeviceHandle *handle, uint8_t vsInterfaceNumber) {
    if (!handle || !handle->deviceInterface) return 0;

    IOUSBFindInterfaceRequest findReq;
    findReq.bInterfaceClass = kUSBVideoInterfaceClass;
    findReq.bInterfaceSubClass = 0x02; // SC_VIDEOSTREAMING
    findReq.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
    findReq.bAlternateSetting = kIOUSBFindInterfaceDontCare;

    io_iterator_t iter = 0;
    if ((*handle->deviceInterface)->CreateInterfaceIterator(handle->deviceInterface, &findReq, &iter) != kIOReturnSuccess || !iter) {
        return 0;
    }

    uint8_t alt = 0;
    io_service_t svc = 0;
    while ((svc = IOIteratorNext(iter)) != 0) {
        int64_t ifcNum = -1;
        if (read_cfnumber_int64(svc, CFSTR("bInterfaceNumber"), &ifcNum) && (uint8_t)ifcNum == vsInterfaceNumber) {
            int64_t altVal = 0;
            if (read_cfnumber_int64(svc, CFSTR("bAlternateSetting"), &altVal) && altVal >= 0 && altVal <= 255) {
                alt = (uint8_t)altVal;
            }
            IOObjectRelease(svc);
            break;
        }
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);
    return alt;
}

bool cuvc_get_active_stream_state(
    CUVCDeviceHandle *handle,
    uint8_t vsInterfaceNumber,
    CUVCActiveStreamState *outState
) {
    if (!handle || !outState) return false;
    memset(outState, 0, sizeof(CUVCActiveStreamState));

    uint8_t altSetting = query_vs_alternate_setting(handle, vsInterfaceNumber);
    uint16_t blockLen = query_vs_probe_length(handle, vsInterfaceNumber);
    uint8_t buf[64] = {0};

    // Try VS_COMMIT_CONTROL first, fallback to VS_PROBE_CONTROL
    uint8_t selectors[2] = { UVC_VS_COMMIT_CONTROL, UVC_VS_PROBE_CONTROL };
    for (int i = 0; i < 2; i++) {
        memset(buf, 0, sizeof(buf));
        IOUSBDevRequest req;
        memset(&req, 0, sizeof(req));
        req.bmRequestType = USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface);
        req.bRequest = CUVC_REQ_GET_CUR;
        req.wValue = (uint16_t)(selectors[i] << 8);
        req.wIndex = (uint16_t)vsInterfaceNumber;
        req.wLength = blockLen;
        req.pData = buf;

        if (vs_ep0_request(handle, &req) && req.wLenDone >= 26 && buf[2] != 0 && buf[3] != 0) {
            outState->isValid = true;
            outState->videoStreamingInterfaceNumber = vsInterfaceNumber;
            outState->alternateSetting = altSetting;
            outState->formatIndex = buf[2];
            outState->frameIndex = buf[3];
            outState->frameInterval100ns = read_le32(buf + 4);
            outState->maxVideoFrameSize = read_le32(buf + 18);
            outState->maxPayloadTransferSize = read_le32(buf + 22);
            return true;
        }
    }
    return false;
}

bool cuvc_negotiate_stream_state(
    CUVCDeviceHandle *handle,
    uint8_t vsInterfaceNumber,
    uint8_t formatIndex,
    uint8_t frameIndex,
    uint32_t frameInterval100ns,
    bool commitToStream,
    CUVCActiveStreamState *outNegotiated
) {
    if (!handle || formatIndex == 0 || frameIndex == 0 || frameInterval100ns == 0) return false;

    uint16_t blockLen = query_vs_probe_length(handle, vsInterfaceNumber);
    uint8_t probeBuf[64] = {0};

    // Seed probeBuf from current VS_PROBE_CONTROL GET_CUR if available
    IOUSBDevRequest getInitial;
    memset(&getInitial, 0, sizeof(getInitial));
    getInitial.bmRequestType = USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface);
    getInitial.bRequest = CUVC_REQ_GET_CUR;
    getInitial.wValue = (uint16_t)(UVC_VS_PROBE_CONTROL << 8);
    getInitial.wIndex = (uint16_t)vsInterfaceNumber;
    getInitial.wLength = blockLen;
    getInitial.pData = probeBuf;
    vs_ep0_request(handle, &getInitial);

    // bmHint = 0x0001 (keep dwFrameInterval fixed)
    write_le16(probeBuf + 0, 0x0001);
    probeBuf[2] = formatIndex;
    probeBuf[3] = frameIndex;
    write_le32(probeBuf + 4, frameInterval100ns);

    IOUSBDevRequest setProbe;
    memset(&setProbe, 0, sizeof(setProbe));
    setProbe.bmRequestType = USBmakebmRequestType(kUSBOut, kUSBClass, kUSBInterface);
    setProbe.bRequest = CUVC_REQ_SET_CUR;
    setProbe.wValue = (uint16_t)(UVC_VS_PROBE_CONTROL << 8);
    setProbe.wIndex = (uint16_t)vsInterfaceNumber;
    setProbe.wLength = blockLen;
    setProbe.pData = probeBuf;

    if (!vs_ep0_request(handle, &setProbe)) {
        return false;
    }

    // Read back negotiated parameters (populates dwMaxVideoFrameSize & dwMaxPayloadTransferSize)
    uint8_t negotiatedBuf[64] = {0};
    IOUSBDevRequest getNegotiated;
    memset(&getNegotiated, 0, sizeof(getNegotiated));
    getNegotiated.bmRequestType = USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface);
    getNegotiated.bRequest = CUVC_REQ_GET_CUR;
    getNegotiated.wValue = (uint16_t)(UVC_VS_PROBE_CONTROL << 8);
    getNegotiated.wIndex = (uint16_t)vsInterfaceNumber;
    getNegotiated.wLength = blockLen;
    getNegotiated.pData = negotiatedBuf;

    if (!vs_ep0_request(handle, &getNegotiated) || getNegotiated.wLenDone < 26) {
        memcpy(negotiatedBuf, probeBuf, blockLen);
    }

    // Preserve requested validated frameInterval100ns in case camera echoed hint loosely
    write_le32(negotiatedBuf + 4, frameInterval100ns);

    if (commitToStream) {
        IOUSBDevRequest setCommit;
        memset(&setCommit, 0, sizeof(setCommit));
        setCommit.bmRequestType = USBmakebmRequestType(kUSBOut, kUSBClass, kUSBInterface);
        setCommit.bRequest = CUVC_REQ_SET_CUR;
        setCommit.wValue = (uint16_t)(UVC_VS_COMMIT_CONTROL << 8);
        setCommit.wIndex = (uint16_t)vsInterfaceNumber;
        setCommit.wLength = blockLen;
        setCommit.pData = negotiatedBuf;

        if (!vs_ep0_request(handle, &setCommit)) {
            return false;
        }
    }

    if (outNegotiated) {
        memset(outNegotiated, 0, sizeof(CUVCActiveStreamState));
        outNegotiated->isValid = true;
        outNegotiated->videoStreamingInterfaceNumber = vsInterfaceNumber;
        outNegotiated->alternateSetting = query_vs_alternate_setting(handle, vsInterfaceNumber);
        outNegotiated->formatIndex = negotiatedBuf[2];
        outNegotiated->frameIndex = negotiatedBuf[3];
        outNegotiated->frameInterval100ns = read_le32(negotiatedBuf + 4);
        outNegotiated->maxVideoFrameSize = read_le32(negotiatedBuf + 18);
        outNegotiated->maxPayloadTransferSize = read_le32(negotiatedBuf + 22);
    }
    return true;
}

// MARK: - VideoControl Endpoint 0 Requests

static bool perform_ep0_request(CUVCDeviceHandle *handle, IOUSBDevRequest *req) {
    if (!handle || !handle->controlInterface) return false;

    IOReturn kr = (*handle->controlInterface)->ControlRequest(handle->controlInterface, 0, req);
    if (kr == kIOReturnSuccess) {
        handle->lastError = 0;
        return true;
    }

    if (handle->deviceInterface) {
        req->wLenDone = 0;
        kr = (*handle->deviceInterface)->DeviceRequest(handle->deviceInterface, req);
        if (kr == kIOReturnSuccess) {
            handle->lastError = 0;
            return true;
        }
    }
    handle->lastError = (int32_t)kr;
    return false;
}

bool cuvc_get_control_bytes(
    CUVCDeviceHandle *handle,
    uint8_t requestCode,
    uint8_t unitId,
    uint8_t selector,
    void *outBuffer,
    uint16_t length,
    uint16_t *outBytesTransferred
) {
    if (!handle || !outBuffer || length == 0) return false;
    memset(outBuffer, 0, length);

    IOUSBDevRequest req;
    memset(&req, 0, sizeof(req));
    req.bmRequestType = USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface);
    req.bRequest = requestCode;
    req.wValue = (uint16_t)(selector << 8);
    req.wIndex = ((uint16_t)unitId << 8) | (uint16_t)handle->info.videoControlInterfaceNumber;
    req.wLength = length;
    req.pData = outBuffer;
    req.wLenDone = 0;

    if (!perform_ep0_request(handle, &req)) {
        return false;
    }
    if (outBytesTransferred) {
        *outBytesTransferred = (uint16_t)req.wLenDone;
    }
    return req.wLenDone > 0;
}

bool cuvc_set_control_bytes(
    CUVCDeviceHandle *handle,
    uint8_t unitId,
    uint8_t selector,
    const void *inBuffer,
    uint16_t length
) {
    if (!handle || !inBuffer || length == 0) return false;

    uint8_t tempBuf[64];
    if (length > sizeof(tempBuf)) return false;
    memcpy(tempBuf, inBuffer, length);

    IOUSBDevRequest req;
    memset(&req, 0, sizeof(req));
    req.bmRequestType = USBmakebmRequestType(kUSBOut, kUSBClass, kUSBInterface);
    req.bRequest = CUVC_REQ_SET_CUR;
    req.wValue = (uint16_t)(selector << 8);
    req.wIndex = ((uint16_t)unitId << 8) | (uint16_t)handle->info.videoControlInterfaceNumber;
    req.wLength = length;
    req.pData = tempBuf;
    req.wLenDone = 0;

    return perform_ep0_request(handle, &req);
}

bool cuvc_get_info(CUVCDeviceHandle *handle, uint8_t unitId, uint8_t selector, uint8_t *outInfo) {
    if (!outInfo) return false;
    uint16_t transferred = 0;
    return cuvc_get_control_bytes(handle, CUVC_REQ_GET_INFO, unitId, selector, outInfo, 1, &transferred);
}

bool cuvc_get_int(
    CUVCDeviceHandle *handle,
    uint8_t requestCode,
    uint8_t unitId,
    uint8_t selector,
    uint8_t byteLength,
    bool isSigned,
    int64_t *outValue
) {
    if (!outValue) return false;
    uint8_t buf[8] = {0};
    uint16_t transferred = 0;
    if (byteLength != 1 && byteLength != 2 && byteLength != 4) return false;

    if (!cuvc_get_control_bytes(handle, requestCode, unitId, selector, buf, byteLength, &transferred)) {
        return false;
    }

    switch (byteLength) {
        case 1:
            *outValue = isSigned ? (int64_t)((int8_t)buf[0]) : (int64_t)buf[0];
            return true;
        case 2: {
            uint16_t host = read_le16(buf);
            *outValue = isSigned ? (int64_t)((int16_t)host) : (int64_t)host;
            return true;
        }
        case 4: {
            uint32_t host = read_le32(buf);
            *outValue = isSigned ? (int64_t)((int32_t)host) : (int64_t)host;
            return true;
        }
        default:
            return false;
    }
}

bool cuvc_set_int(
    CUVCDeviceHandle *handle,
    uint8_t unitId,
    uint8_t selector,
    uint8_t byteLength,
    bool isSigned,
    int64_t value
) {
    (void)isSigned;
    uint8_t buf[4] = {0};
    switch (byteLength) {
        case 1:
            buf[0] = (uint8_t)(value & 0xFF);
            break;
        case 2:
            write_le16(buf, (uint16_t)(value & 0xFFFF));
            break;
        case 4:
            write_le32(buf, (uint32_t)(value & 0xFFFFFFFFu));
            break;
        default:
            return false;
    }
    return cuvc_set_control_bytes(handle, unitId, selector, buf, byteLength);
}

bool cuvc_get_pantilt(
    CUVCDeviceHandle *handle,
    uint8_t requestCode,
    uint8_t unitId,
    int32_t *outPan,
    int32_t *outTilt
) {
    if (!outPan || !outTilt) return false;
    uint8_t buf[8] = {0};
    uint16_t transferred = 0;
    if (!cuvc_get_control_bytes(handle, requestCode, unitId, CUVC_CT_PANTILT_ABSOLUTE_CONTROL, buf, 8, &transferred)) {
        return false;
    }
    *outPan = (int32_t)read_le32(buf);
    *outTilt = (int32_t)read_le32(buf + 4);
    return true;
}

bool cuvc_set_pantilt(
    CUVCDeviceHandle *handle,
    uint8_t unitId,
    int32_t pan,
    int32_t tilt
) {
    uint8_t buf[8] = {0};
    write_le32(buf, (uint32_t)pan);
    write_le32(buf + 4, (uint32_t)tilt);
    return cuvc_set_control_bytes(handle, unitId, CUVC_CT_PANTILT_ABSOLUTE_CONTROL, buf, 8);
}

static void drain_iterator(io_iterator_t iterator) {
    if (!iterator) return;
    io_service_t obj = 0;
    while ((obj = IOIteratorNext(iterator)) != 0) {
        IOObjectRelease(obj);
    }
}

static void hotplug_io_callback(void *refcon, io_iterator_t iterator) {
    drain_iterator(iterator);
    CUVCHotplugWatcher *watcher = (CUVCHotplugWatcher *)refcon;
    if (watcher && watcher->callback) {
        watcher->callback(watcher->context);
    }
}

CUVCHotplugWatcher *cuvc_start_hotplug_watcher(CUVCHotplugCallback callback, void *context) {
    IONotificationPortRef port = IONotificationPortCreate(kIOMainPortDefault);
    if (!port) return NULL;

    CUVCHotplugWatcher *watcher = (CUVCHotplugWatcher *)calloc(1, sizeof(CUVCHotplugWatcher));
    if (!watcher) {
        IONotificationPortDestroy(port);
        return NULL;
    }
    watcher->notifyPort = port;
    watcher->callback = callback;
    watcher->context = context;

    CFRunLoopSourceRef source = IONotificationPortGetRunLoopSource(port);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);

    CFMutableDictionaryRef matchAdded = IOServiceMatching(kIOUSBDeviceClassName);
    if (matchAdded) {
        if (IOServiceAddMatchingNotification(
                port,
                kIOMatchedNotification,
                matchAdded,
                hotplug_io_callback,
                watcher,
                &watcher->addedIter
            ) == KERN_SUCCESS) {
            drain_iterator(watcher->addedIter);
        }
    }

    CFMutableDictionaryRef matchRemoved = IOServiceMatching(kIOUSBDeviceClassName);
    if (matchRemoved) {
        if (IOServiceAddMatchingNotification(
                port,
                kIOTerminatedNotification,
                matchRemoved,
                hotplug_io_callback,
                watcher,
                &watcher->removedIter
            ) == KERN_SUCCESS) {
            drain_iterator(watcher->removedIter);
        }
    }

    return watcher;
}

void cuvc_stop_hotplug_watcher(CUVCHotplugWatcher *watcher) {
    if (!watcher) return;
    if (watcher->addedIter) {
        IOObjectRelease(watcher->addedIter);
        watcher->addedIter = 0;
    }
    if (watcher->removedIter) {
        IOObjectRelease(watcher->removedIter);
        watcher->removedIter = 0;
    }
    if (watcher->notifyPort) {
        IONotificationPortDestroy(watcher->notifyPort);
        watcher->notifyPort = NULL;
    }
    free(watcher);
}
