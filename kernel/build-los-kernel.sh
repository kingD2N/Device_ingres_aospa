#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: kingD2N
# SPDX-License-Identifier: Apache-2.0
#
# Build the LineageOS 24 kernel for ingres from source inside an AOSPA tree and
# install it into the AOSPA prebuilt kernel dir (KERNEL_PREBUILT_DIR), so the
# ROM build picks it up like any prebuilt kernel. It mirrors what LineageOS'
# vendor/lineage/build/tasks/kernel.mk does for sm8450-common (lineage-24.0):
#
#   - config : gki_defconfig + vendor/waipio_GKI + xiaomi_GKI + ingres_GKI + debugfs
#   - kernel : Image, in-tree modules, dtbs (TARGET_PRODUCT=ingres TARGET_BOARD_PLATFORM=taro)
#   - modules: kernel/xiaomi/sm8450-modules (same 18 techpack modules as LineageOS)
#   - dtb/dtbo: QCOM merge_dtbs.py (base dtbs + techpack overlays), mkdtboimg
#   - lists  : first stage = kernel modules.list.msm.waipio,
#              second stage / vendor_dlkm = lists from LineageOS sm8450-common
#
# Output layout (device/xiaomi/ingres-kernel, read by device/qcom/common/dlkm/kernel-platform.mk):
#   Image, System.map, Module.symvers, dtbs/waipio.dtb, dtbs/dtbo.img,
#   vendor_ramdisk/*.ko + modules.load (+ .recovery), vendor_dlkm/*.ko + modules.load + modules.blocklist
#
# Run from the root of the ROM tree:  device/xiaomi/ingres/kernel/build-los-kernel.sh
#
# Environment overrides:
#   JOBS=<n>          parallel jobs (default: nproc)
#   KERNEL_CLEAN=1    start the kernel build from scratch

set -euo pipefail

TOP="$(pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KSRC=kernel/xiaomi/sm8450
KMOD=kernel/xiaomi/sm8450-modules
KDT=kernel/xiaomi/sm8450-devicetrees
PREBUILT=device/xiaomi/ingres-kernel
WORK="$TOP/out/los-kernel"
KOBJ="$WORK/KERNEL_OBJ"
STAGE="$WORK/modules"
TOOLS="$WORK/host"
JOBS="${JOBS:-$(nproc)}"

FRAGMENTS="vendor/waipio_GKI.config vendor/xiaomi_GKI.config vendor/ingres_GKI.config vendor/debugfs.config"
EXT_MODULES="
qcom/opensource/mmrm-driver
qcom/opensource/audio-kernel
qcom/opensource/camera-kernel
qcom/opensource/cvp-kernel
qcom/opensource/dataipa/drivers/platform/msm
qcom/opensource/datarmnet/core
qcom/opensource/datarmnet-ext/aps
qcom/opensource/datarmnet-ext/offload
qcom/opensource/datarmnet-ext/shs
qcom/opensource/datarmnet-ext/perf
qcom/opensource/datarmnet-ext/perf_tether
qcom/opensource/datarmnet-ext/sch
qcom/opensource/datarmnet-ext/wlan
qcom/opensource/display-drivers/msm
qcom/opensource/eva-kernel
qcom/opensource/video-driver
qcom/opensource/wlan/qcacld-3.0/.qca6490
qcom/opensource/wlan/qcacld-3.0/.qca6750
"

log() { echo -e "\033[1;34m[kernel-los]\033[0m $*"; }
die() { echo -e "\033[1;31m[kernel-los]\033[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------- checks
for d in "$KSRC" "$KMOD" "$KDT" "$PREBUILT" prebuilts/kernel-build-tools/linux-x86 \
         prebuilts/build-tools/linux-x86/bin system/libufdt/utils/src; do
    [ -e "$d" ] || die "$d tidak ada. Sync dulu (local manifest AOSPA berisi source kernel LineageOS 24)."
done
[ -f "$KSRC/arch/arm64/configs/vendor/ingres_GKI.config" ] || die "$KSRC bukan kernel LineageOS ingres (vendor/ingres_GKI.config tidak ada)"
miss=""
for t in bc perl python3 cpio git; do command -v "$t" >/dev/null || miss="$miss $t"; done
[ -z "$miss" ] || die "Alat host belum terpasang:$miss"

# Toolchain: AOSP default clang of this tree (same as LineageOS' LLVM_AOSP_PREBUILTS_VERSION)
CLANG_VER="$(sed -n 's/.*ClangDefaultVersion *= *"\(clang-r[^"]*\)".*/\1/p' build/soong/cc/config/global.go 2>/dev/null | head -n1)"
CLANG="$TOP/prebuilts/clang/host/linux-x86/${CLANG_VER:-none}"
[ -x "$CLANG/bin/clang" ] || CLANG="$(ls -d "$TOP"/prebuilts/clang/host/linux-x86/clang-r* 2>/dev/null | sort -V | tail -n1)"
[ -x "$CLANG/bin/clang" ] || die "clang tidak ditemukan di prebuilts/clang/host/linux-x86"
BT="$TOP/prebuilts/build-tools/linux-x86"
KBT="$TOP/prebuilts/kernel-build-tools/linux-x86"
SYSROOT="$TOP/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot"
export PATH="$TOOLS:$BT/bin:$CLANG/bin:$PATH"
export LD_LIBRARY_PATH="$CLANG/lib64:${LD_LIBRARY_PATH:-}"
export BISON_PKGDATADIR="$TOP/prebuilts/build-tools/common/bison"
export HIP_PATH=none
log "clang: $(basename "$CLANG")"

CCV="clang"
if [ -n "${CCACHE_EXEC:-}" ] && [ -x "${CCACHE_EXEC}" ]; then CCV="${CCACHE_EXEC} clang"; fi

HOSTCFLAGS="-I$KBT/include"
HOSTLDFLAGS="-Wl,-rpath,$KBT/lib64 -L $KBT/lib64 -fuse-ld=lld --rtlib=compiler-rt"
if [ -d "$SYSROOT" ]; then
    HOSTCFLAGS="--sysroot=$SYSROOT $HOSTCFLAGS"
    HOSTLDFLAGS="--sysroot=$SYSROOT $HOSTLDFLAGS"
fi
MAKE="$BT/bin/make"
KFLAGS=(-j"$JOBS" "HOSTCFLAGS=$HOSTCFLAGS" "HOSTLDFLAGS=$HOSTLDFLAGS"
        LLVM=1 LLVM_IAS=1 "LZ4=$KBT/bin/lz4" "LEX=$BT/bin/flex" "YACC=$BT/bin/bison"
        "M4=$BT/bin/m4" "PAHOLE=$KBT/bin/pahole" TARGET_PRODUCT=ingres TARGET_BOARD_PLATFORM=taro
        ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- "CC=$CCV" LD=ld.lld "DTC_EXT=$TOOLS/dtc")

kmake() { "$MAKE" "${KFLAGS[@]}" -C "$KSRC" O="$KOBJ" "$@"; }

[ "${KERNEL_CLEAN:-0}" = 1 ] && rm -rf "$WORK"
mkdir -p "$KOBJ" "$TOOLS"

# ------------------------------------------- host tools (dtc / fdt*, like LineageOS)
build_host_tools() {
    local src="$WORK/dtc-src" lib cf
    [ -x "$TOOLS/dtc" ] && [ -x "$TOOLS/fdtoverlaymerge" ] && return 0
    log "Membuat alat host dtc/fdtget/fdtput/fdtoverlay/fdtoverlaymerge"
    rm -rf "$src"
    git clone -q --depth=1 -b lineage-24.0 https://github.com/LineageOS/android_external_dtc "$src" \
        || die "Gagal mengambil LineageOS/android_external_dtc"
    echo '#define DTC_VERSION "DTC 1.7.x-lineage"' > "$src/version_gen.h"
    lib="$(ls "$src"/libfdt/*.c)"
    cf=(-O2 -DNO_YAML -Wno-macro-redefined -Wno-unused-parameter -I"$src" -I"$src/libfdt")
    ( cd "$src" && bison -d -o dtc-parser.tab.c dtc-parser.y && flex -o dtc-lexer.lex.c dtc-lexer.l ) \
        || die "bison/flex gagal untuk dtc"
    # shellcheck disable=SC2086
    clang "${cf[@]}" -o "$TOOLS/dtc" "$src"/{checks,data,dtc,flattree,fstree,livetree,srcpos,treesource,util}.c \
        "$src/dtc-lexer.lex.c" "$src/dtc-parser.tab.c" $lib || die "Gagal compile dtc"
    for t in fdtget fdtput fdtoverlay fdtoverlaymerge; do
        # shellcheck disable=SC2086
        clang "${cf[@]}" -o "$TOOLS/$t" "$src/$t.c" "$src/util.c" $lib || die "Gagal compile $t"
    done
    # merge_dtbs.py hanya memakai ufdt_apply_overlay sebagai pemeriksaan tambahan
    printf '#!/bin/sh\nexit 0\n' > "$TOOLS/ufdt_apply_overlay"; chmod +x "$TOOLS/ufdt_apply_overlay"
}
build_host_tools

# ---------------------------------------------------------------- config
log "Kernel: $KSRC ($(git -C "$KSRC" rev-parse --short HEAD 2>/dev/null || echo ?)), $JOBS job"
cp "$KSRC/arch/arm64/configs/gki_defconfig" "$KOBJ/.config"
kmake olddefconfig
for f in $FRAGMENTS; do
    ( cd "$KOBJ" && "$TOP/$KSRC/scripts/kconfig/merge_config.sh" -m -O "$KOBJ" "$KOBJ/.config" "$TOP/$KSRC/arch/arm64/configs/$f" ) >/dev/null
    kmake olddefconfig
done

# ---------------------------------------------------------------- build
log "Image"
kmake Image
log "DTB"
kmake dtbs
log "Modul in-tree"
kmake modules
rm -rf "$STAGE"
kmake INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 modules_install
rpath="$(python3 -c 'import os,sys;print(os.path.relpath(*(sys.argv[1:])))' "$KMOD" "$KSRC")"
for p in $EXT_MODULES; do
    log "Modul eksternal: $p"
    for target in "" "INSTALL_MOD_PATH=$STAGE INSTALL_MOD_STRIP=1 KERNEL_UAPI_HEADERS_DIR=$KOBJ modules_install"; do
        # shellcheck disable=SC2086
        "$MAKE" "${KFLAGS[@]}" -C "$KMOD/$p" M="$rpath/$p" KERNEL_SRC="$TOP/$KSRC" \
            OUT_DIR="$KOBJ" O="$KOBJ" $target || die "Gagal build modul $p"
    done
done

# ---------------------------------------------------------------- modules
krel="$(cat "$KOBJ/include/config/kernel.release")"
mdir="$STAGE/lib/modules/$krel"
mapfile -t ALL < <(find "$mdir" -type f -name '*.ko' | sort)
log "Total modul: ${#ALL[@]} ($krel)"
dups="$(printf '%s\n' "${ALL[@]}" | xargs -n1 basename | sort | uniq -d)"
[ -z "$dups" ] || die "Modul ganda: $dups"
if command -v depmod >/dev/null; then
    tmp="$WORK/depmod"; rm -rf "$tmp"; mkdir -p "$tmp/lib/modules/0.0"
    cp "${ALL[@]}" "$tmp/lib/modules/0.0/"
    depmod -ae -F "$KOBJ/System.map" -b "$tmp" 0.0 2> "$tmp/err" || true
    if grep -q "needs unknown symbol" "$tmp/err"; then
        cat "$tmp/err" >&2; die "Ada modul yang butuh simbol yang tidak ada di kernel"
    fi
fi

# baca daftar: buang komentar/baris kosong, nama dasar + .ko
readlist() { sed -e 's/#.*//' -e 's#.*/##' -e 's/[[:space:]]//g' -e '/^$/d' -e '/\.ko$/! s/$/.ko/' "$1"; }
modpath() { printf '%s\n' "${ALL[@]}" | grep -m1 "/$1\$" || true; }

mapfile -t FIRST < <(readlist "$KSRC/modules.list.msm.waipio")
mapfile -t SECOND < <(readlist "$HERE/modules.list.second_stage")
mapfile -t EXCL < <(readlist "$HERE/modules.list.vendor_dlkm")

for m in "${FIRST[@]}" "${SECOND[@]}" "${EXCL[@]}"; do
    [ -n "$(modpath "$m")" ] || die "$m ada di daftar modul tapi tidak ter-build"
done

log "Memasang ke $PREBUILT"
rm -rf "$PREBUILT/vendor_ramdisk" "$PREBUILT/vendor_dlkm" "$PREBUILT/dtbs"
mkdir -p "$PREBUILT/vendor_ramdisk" "$PREBUILT/vendor_dlkm" "$PREBUILT/dtbs"
# vendor_ramdisk: modul tahap 1 + 2 (load: tahap 1, recovery: tahap 1 + 2)
for m in "${FIRST[@]}" "${SECOND[@]}"; do cp "$(modpath "$m")" "$PREBUILT/vendor_ramdisk/"; done
printf '%s\n' "${FIRST[@]}" > "$PREBUILT/vendor_ramdisk/modules.load"
printf '%s\n' "${FIRST[@]}" "${SECOND[@]}" > "$PREBUILT/vendor_ramdisk/modules.load.recovery"
# vendor_dlkm: semua modul (load: tahap 2 + khusus vendor_dlkm)
cp "${ALL[@]}" "$PREBUILT/vendor_dlkm/"
printf '%s\n' "${SECOND[@]}" "${EXCL[@]}" > "$PREBUILT/vendor_dlkm/modules.load"
cp "$KSRC/modules.vendor_blocklist.msm.waipio" "$PREBUILT/vendor_dlkm/modules.blocklist"

# ---------------------------------------------------------------- dtb / dtbo
log "Merge DTB (merge_dtbs.py) dan dtbo.img"
base="$WORK/dtbs-base"; merged="$WORK/dtbs-out"
rm -rf "$base" "$merged"; mkdir -p "$base" "$merged"
dts="$KOBJ/arch/arm64/boot/dts/vendor"
mv "$dts"/*/*.dtb "$dts"/*/*.dtbo "$base"/ 2>/dev/null || true
ls "$base"/*.dtb >/dev/null 2>&1 || die "Tidak ada DTB dasar di $dts"
python3 "$HERE/merge_dtbs.py" --base "$base" --techpack "$dts" --out "$merged"
mapfile -t DTB < <(find "$merged" -type f -name '*.dtb' | sort)
mapfile -t DTBO < <(find "$merged" -type f -name '*.dtbo' | sort)
[ "${#DTB[@]}" -gt 0 ] && [ "${#DTBO[@]}" -gt 0 ] || die "merge_dtbs.py tidak menghasilkan dtb/dtbo"
cat "${DTB[@]}" > "$PREBUILT/dtbs/waipio.dtb"
python3 system/libufdt/utils/src/mkdtboimg.py create "$PREBUILT/dtbs/dtbo.img" --page_size=4096 "${DTBO[@]}"

cp "$KOBJ/arch/arm64/boot/Image" "$KOBJ/System.map" "$KOBJ/Module.symvers" "$PREBUILT/"

log "Selesai: $(strings "$PREBUILT/Image" | grep -m1 '^Linux version 5' | cut -d' ' -f3)," \
    "${#FIRST[@]} modul tahap 1, ${#SECOND[@]} tahap 2, $(( ${#SECOND[@]} + ${#EXCL[@]} )) vendor_dlkm," \
    "${#DTB[@]} dtb, ${#DTBO[@]} dtbo"
