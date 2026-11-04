#
# Copyright (C) 2021 The Android Open Source Project
#           (C) 2022-2025 Paranoid Android
#
# SPDX-License-Identifier: Apache-2.0
#

# /data tanpa enkripsi (decrypt). Wajib format data saat pertama kali flash.
# Build terenkripsi: DECRYPT=0 bash <script build>
TARGET_DECRYPTED_DATA ?= true

# Dolby UI: LunarisDolby (dari paket tambahan), bukan XiaomiDolby
TARGET_USES_LUNARIS_DOLBY := true

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

# SELinux Treble Labeling (Android 17): label app GameKeys/MIUI Camera/Dolby dari
# paket tambahan ada di sepolicy vendor; laporkan sebagai peringatan saja
PRODUCT_ENFORCE_SELINUX_TREBLE_LABELING := false

# Shipping API
PRODUCT_SHIPPING_API_LEVEL := 31

# Paket tambahan: GameKeys, LED, Dolby Lunaris, JamesDSP, MIUI Camera
# (vendor/ingres/addons, lihat local manifest)
INGRES_ADDONS_ROM := aospa
$(call inherit-product-if-exists, vendor/ingres/addons/addons.mk)

# Vendor blobs
$(call inherit-product, vendor/xiaomi/ingres/ingres-vendor.mk)
