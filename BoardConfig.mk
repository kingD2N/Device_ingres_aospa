#
# Copyright (C) 2021 The Android Open Source Project
#           (C) 2022-2024 Paranoid Android
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/xiaomi/ingres

# /data tanpa enkripsi (lihat device.mk), dipakai fstab recovery
TARGET_DECRYPTED_DATA ?= true

# Inherit from sm8450-common
include device/xiaomi/sm8450-common/BoardConfigCommon.mk

# Bootloader
TARGET_BOARD_INFO_FILE := $(DEVICE_PATH)/board-info.txt
TARGET_BOOTLOADER_BOARD_NAME := ingres

# Firmware (optional, not shipped by default)
-include vendor/xiaomi/ingres-firmware/config.mk

# Init
TARGET_INIT_VENDOR_LIB := //$(DEVICE_PATH):libinit_ingres
TARGET_RECOVERY_DEVICE_MODULES := libinit_ingres

# OTA
TARGET_OTA_ASSERT_DEVICE := ingres

# Screen density
TARGET_SCREEN_DENSITY := 395

# Properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/properties/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/properties/vendor.prop

# Paket tambahan (GameKeys, LED, Dolby Lunaris, JamesDSP, MIUI Camera)
INGRES_ADDONS_ROM := aospa
-include vendor/ingres/addons/BoardConfigAddons.mk
