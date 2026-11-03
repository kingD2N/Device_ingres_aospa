#
# Copyright (C) 2024 Paranoid Android
#
# SPDX-License-Identifier: Apache-2.0
#

# ingres is not in vendor/aospa/products, so the product lives in the device tree.
PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/aospa_ingres.mk

COMMON_LUNCH_CHOICES := \
    aospa_ingres-userdebug \
    aospa_ingres-user
