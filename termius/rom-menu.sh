#!/usr/bin/env bash
#
# Menu build ROM ingres (POCO F4 GT) untuk Termius - pilih ROM, pilih perintah, jalan.
# Script build ROM selalu diunduh versi terbaru dari GitHub sebelum dijalankan.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/rom-menu.sh)
#
# Langsung tanpa menu (untuk snippet satu klik):
#   bash <(curl -fsSL .../rom-menu.sh) evox            # sync + build
#   bash <(curl -fsSL .../rom-menu.sh) evox status     # perintah lain: build, sync, status, upload, clean
#   GAPPS=0 bash <(curl -fsSL .../rom-menu.sh) lunaris # pengaturan ditulis di depan seperti biasa

set -uo pipefail

RAW=https://raw.githubusercontent.com/kingD2N
DEV=android_device_xiaomi_ingres-old

# kunci | nama | repo/branch/script | pengaturan bawaan
ROMS=(
    "evox|Evolution X 12.4 (A17)|$DEV/evox-cnb/build-evox.sh|"
    "los24|LineageOS 24 (A17)|$DEV/lineage-24.0/build-ingres.sh|"
    "pixelos|PixelOS (A17)|$DEV/pixelos-17/build-pixelos.sh|"
    "lunaris|Lunaris-AOSP (A16)|$DEV/lunaris-16.2/build-lunaris.sh|"
    "alpha|AlphaDroid 4.7 (A16)|$DEV/alpha-16.2/build-alpha.sh|"
    "axion|AxionOS (A16)|$DEV/axion-23.2/build-axion.sh|"
    "ascp|ASCP (A17)|$DEV/ascp-17/build-ascp.sh|"
    "infinity|Infinity X (A17)|$DEV/infinity-17/build-infinity.sh|"
    "uwu|uwuAOSP (A17)|$DEV/uwu-17.0/build-uwu.sh|"
    "aospa|AOSPA calcite (A17)|Device_ingres_aospa/main/build-aospa.sh|ROM=aospa"
    "penguin|PenguinOS (A17)|Device_ingres_aospa/main/build-aospa.sh|ROM=penguin"
)
ACTIONS=(
    "|sync + build (dari awal)"
    "build|build saja (lanjut build sebelumnya)"
    "status|lihat progres build yang sedang jalan"
    "sync|sync source saja"
    "upload|upload ulang hasil ke GoFile"
    "clean|hapus hasil build lama (out/)"
)

c_ok=$'\e[1;32m'; c_in=$'\e[1;34m'; c_er=$'\e[1;31m'; c_0=$'\e[0m'
die() { echo "${c_er}[GAGAL]${c_0} $*" >&2; exit 1; }

find_rom() {
    local r
    for r in "${ROMS[@]}"; do
        [ "${r%%|*}" = "$1" ] && { echo "$r"; return 0; }
    done
    return 1
}

pick_rom() {
    local i=1 r n
    echo "${c_in}== Pilih ROM ==${c_0}" >&2
    for r in "${ROMS[@]}"; do
        n="${r#*|}"; printf '  %2d) %s\n' $i "${n%%|*}" >&2
        i=$((i + 1))
    done
    read -rp "Nomor ROM: " n
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#ROMS[@]} ] || die "Pilihan ROM tidak ada"
    echo "${ROMS[$((n - 1))]}"
}

pick_action() {
    local i=1 a n
    echo "${c_in}== Pilih perintah ==${c_0}" >&2
    for a in "${ACTIONS[@]}"; do
        printf '  %d) %s\n' $i "${a#*|}" >&2
        i=$((i + 1))
    done
    read -rp "Nomor perintah [1]: " n
    n="${n:-1}"
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#ACTIONS[@]} ] || die "Pilihan perintah tidak ada"
    a="${ACTIONS[$((n - 1))]}"
    echo "${a%%|*}"
}

if [ $# -ge 1 ]; then
    rom=$(find_rom "$1") || die "ROM '$1' tidak dikenal. Pilihan: $(printf '%s ' "${ROMS[@]%%|*}")"
    action="${2:-}"
    extra=""
else
    rom=$(pick_rom) || exit 1
    action=$(pick_action) || exit 1
    echo "Pengaturan tambahan (kosongkan kalau tidak ada), contoh: GAPPS=0 VARIANT=user"
    read -rp "> " extra
fi

key="${rom%%|*}"; rest="${rom#*|}"
name="${rest%%|*}"; rest="${rest#*|}"
path="${rest%%|*}"; preset="${rest#*|}"
script="$HOME/$(basename "$path")"

opts=()
for kv in $preset $extra; do
    [[ "$kv" =~ ^[A-Z_][A-Z0-9_]*=[A-Za-z0-9_./~:-]*$ ]] || die "Pengaturan '$kv' tidak valid (tulis seperti GAPPS=0)"
    [[ "$kv" == *=~/* ]] && kv="${kv%%=*}=$HOME/${kv#*=~/}"
    opts+=("$kv")
done

echo "${c_in}[..]${c_0} Unduh script terbaru: $name"
curl -fsSL -o "$script.new" "$RAW/$path?$(date +%s)" || die "Gagal unduh $RAW/$path"
bash -n "$script.new" || die "Script yang diunduh rusak, coba lagi"
mv -f "$script.new" "$script"

echo "${c_ok}[OK]${c_0} bash $script ${action:-(sync + build)} ${opts[*]:-}"
[ "${MENU_DRY:-0}" = 1 ] && exit 0
if [ ${#opts[@]} -gt 0 ]; then
    exec env "${opts[@]}" bash "$script" ${action:+"$action"}
else
    exec bash "$script" ${action:+"$action"}
fi
