#
# Copyright (C) 2021 The Android Open Source Project
#           (C) 2022-2025 Paranoid Android
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from sm8450-common
$(call inherit-product, device/xiaomi/sm8450-common/common.mk)

# Audio
$(call soong_config_set_bool,android_hardware_audio,skip_speaker_layout_channel_mask_field,true)

# Characteristics
PRODUCT_CHARACTERISTICS := nosdcard

# Kernel (prebuilt: device/xiaomi/ingres-kernel)
KERNEL_PREBUILT_DIR := $(LOCAL_PATH)-kernel

# Keylayout
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/keylayout/uinput-fpc.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/uinput-fpc.kl \
    $(LOCAL_PATH)/configs/keylayout/uinput-goodix.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/uinput-goodix.kl

# Namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

# Overlays
PRODUCT_PACKAGES += \
    AOSPAIngresFrameworksOverlay \
    IngresApertureOverlay \
    IngresFrameworksOverlay \
    IngresNfcOverlay \
    IngresSettingsProviderOverlay \
    IngresSystemUIOverlay \
    IngresWifiOverlay

# Shipping API
PRODUCT_SHIPPING_API_LEVEL := 31

# Vendor blobs
$(call inherit-product, vendor/xiaomi/ingres/ingres-vendor.mk)
