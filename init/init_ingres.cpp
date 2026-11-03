/*
 * Copyright (C) 2021 The LineageOS Project
 *           (C) 2024 Paranoid Android
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <libinit_variant.h>

#include "vendor_init.h"

static const variant_info_t ingres = {
    .hwc = "CN",
    .brand = "Redmi",
    .device = "ingres",
    .model = "22011211C",
    .name = "ingres",
    .mod_device = "ingres",
    .marketname = "Redmi K50 Gaming",
};

static const variant_info_t ingres_global = {
    .hwc = "GL",
    .brand = "POCO",
    .device = "ingres",
    .model = "21121210G",
    .name = "ingres_global",
    .mod_device = "ingres_global",
    .marketname = "POCO F4 GT",
};

// Some global units report ro.boot.hwc=GLOBAL instead of GL
static variant_info_t make_global_alias() {
    variant_info_t v = ingres_global;
    v.hwc = "GLOBAL";
    return v;
}

static const std::vector<variant_info_t> variants = {
    ingres,
    ingres_global,
    make_global_alias(),
};

void vendor_load_properties() {
    search_set_variant_props(variants);
}
