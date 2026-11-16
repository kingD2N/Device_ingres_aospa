#!/usr/bin/env bash
#
# Menu build ROM ingres (POCO F4 GT) untuk Termius - pilih ROM, pilih perintah, jalan.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/rom-menu.sh)
#
# Langsung tanpa menu (untuk snippet satu klik):
#   bash <(curl -fsSL .../rom-menu.sh) evox            # sync + build
#   bash <(curl -fsSL .../rom-menu.sh) evox status     # perintah lain: build, sync, status, upload, clean, bersih
#   GAPPS=0 bash <(curl -fsSL .../rom-menu.sh) lunaris # pengaturan ditulis di depan seperti biasa
#
# Pembaruan otomatis:
#  - Menu ini dan script build ROM selalu diunduh versi terbaru dari GitHub.
#  - Versi ROM dipilih otomatis: branch device tree terbaru untuk ROM itu
#    (mis. lunaris-16.2 -> lunaris-17 begitu branch-nya dibuat).
#  - Kalau source resmi ROM sudah punya versi Android lebih baru tapi device tree
#    belum siap, menu memberi tahu. ROM tetap dibuild dengan versi terakhir yang siap.

set -uo pipefail

RAW=https://raw.githubusercontent.com/kingD2N
GH=https://github.com
DEV=android_device_xiaomi_ingres-old

# kunci ; nama ; awalan branch device tree ; branch cadangan ; script ; repo resmi ; pola branch resmi ; pengaturan ;
#   varian bawaan ; daftar varian ; GApps bawaan ; daftar GApps (nilai=label, nilai kosong = tidak ada pilihan)
ROMS=(
    "evox;Evolution X;evox-;evox-cnb;build-evox.sh;Evolution-X/manifest;^[a-z]{3}$;;user;user,userdebug;1;1=GApps,0=Vanilla,both=GApps + Vanilla"
    "los24;LineageOS;lineage-;lineage-24.0;build-ingres.sh;LineageOS/android;^lineage-[0-9]+\.[0-9]+$;;user;user,userdebug;;=Vanilla saja (LineageOS tanpa GApps)"
    "pixelos;PixelOS;pixelos-;pixelos-17;build-pixelos.sh;PixelOS-AOSP/android_manifest;^(fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)$;;user;user,userdebug,both;;=GApps bawaan (tidak ada vanilla)"
    "lunaris;Lunaris;lunaris-;lunaris-16.2;build-lunaris.sh;Lunaris-AOSP/android;^[0-9]+(\.[0-9]+)?$;;userdebug;user,userdebug,both;1;1=GApps,0=Vanilla,both=GApps + Vanilla"
    "alpha;AlphaDroid;alpha-;alpha-16.2;build-alpha.sh;AlphaDroid-Project/manifest;^alpha-[0-9]+(\.[0-9]+)?$;;userdebug;user,userdebug,both;1;1=GApps,0=Vanilla,both=GApps + Vanilla"
    "axion;AxionOS;axion-;axion-23.2;build-axion.sh;AxionAOSP/android;^lineage-[0-9]+\.[0-9]+$;;user;user,userdebug;gms;gms=GApps lengkap,pico=GApps minimal,core=GApps inti,0=Vanilla"
    "ascp;ASCP;ascp-;ascp-17;build-ascp.sh;Pixelify-AOSP/platform_manifest;^[0-9]+(\.[0-9]+)?$;;user;user,userdebug;;=GApps bawaan (tidak ada vanilla)"
    "infinity;Infinity X;infinity-;infinity-17;build-infinity.sh;ProjectInfinity-X/manifest;^[0-9]+(\.[0-9]+)?$;;user;user,userdebug;1;1=GApps,0=Vanilla"
    "uwu;uwuAOSP;uwu-;uwu-17.0;build-uwu.sh;uwuAOSP/platform_manifests;^uwu-[0-9]+(\.[0-9]+)?$;;user;user,userdebug;;=GApps bawaan (tidak ada vanilla)"
    "aospa;AOSPA;;;build-aospa.sh;;;ROM=aospa;user;user,userdebug;;=GApps bawaan (tidak ada vanilla)"
    "penguin;PenguinOS;;;build-aospa.sh;;;ROM=penguin;user;user,userdebug;;=Bawaan PenguinOS,1=GApps,0=Vanilla"
)
ALIASES="lineage=los24 los=los24 pixel=pixelos alphadroid=alpha infinityx=infinity uwuaosp=uwu"
# Branch device tree yang dilewati (source resmi privat / belum bisa dibuild)
BLOCKED=" alpha-17.0 "
ACTIONS=(
    "|sync + build (dari awal)"
    "build|build saja (lanjut build sebelumnya)"
    "status|lihat progres build yang sedang jalan"
    "sync|sync source saja"
    "upload|upload ulang hasil ke GoFile"
    "clean|hapus hasil build lama (out/)"
    "bersih|hapus source ROM LAIN (ROM pilihan tetap aman, ada konfirmasi YA)"
)

c_ok=$'\e[1;32m'; c_in=$'\e[1;34m'; c_wr=$'\e[1;33m'; c_er=$'\e[1;31m'; c_0=$'\e[0m'
die() { echo "${c_er}[GAGAL]${c_0} $*" >&2; exit 1; }

# Nomor versi Android dari nama branch, untuk dibandingkan: 17, 16.2, lineage-24.0,
# seventeen, cnb (kode huruf: u=14 v=15 b=16 c=17 d=18 ...). Gagal kalau tidak dikenali.
verkey() {
    local s="$1" n major minor=0 l
    case "$s" in
        fourteen) major=14 ;; fifteen) major=15 ;; sixteen) major=16 ;; seventeen) major=17 ;;
        eighteen) major=18 ;; nineteen) major=19 ;; twenty) major=20 ;;
        *[0-9]*)
            n=$(grep -oE '[0-9]+(\.[0-9]+)?' <<<"$s" | tail -n 1)
            major=${n%%.*}; [ "$n" != "$major" ] && minor=${n#*.} ;;
        [a-z][a-z][a-z])
            l=$(printf '%d' "'${s:0:1}")
            if [ "$l" -ge 117 ]; then major=$((14 + l - 117)); else major=$((16 + l - 98)); fi ;;
        *) return 1 ;;
    esac
    printf '%04d.%04d\n' "$((10#$major))" "$((10#$minor))"
}

# Branch dengan versi tertinggi dari daftar (satu per baris).
newest() {
    local b k best="" bestk=""
    while read -r b; do
        [ -n "$b" ] || continue
        k=$(verkey "$b") || continue
        if [ -z "$bestk" ] || [[ "$k" > "$bestk" ]]; then best="$b"; bestk="$k"; fi
    done
    echo "$best"
}

heads() { timeout 40 git ls-remote --heads "$1" 2>/dev/null | sed 's|.*refs/heads/||'; }

find_rom() {
    local r k="$1" a
    for a in $ALIASES; do [ "${a%%=*}" = "$k" ] && k="${a#*=}"; done
    for r in "${ROMS[@]}"; do
        [ "${r%%;*}" = "$k" ] && { echo "$r"; return 0; }
    done
    return 1
}

pick_rom() {
    local i=1 r n
    echo "${c_in}== Pilih ROM ==${c_0}" >&2
    for r in "${ROMS[@]}"; do
        n="${r#*;}"; printf '  %2d) %s\n' $i "${n%%;*}" >&2
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

args=()
extra=""
if [ $# -ge 1 ]; then
    rom=$(find_rom "$1") || die "ROM '$1' tidak dikenal. Pilihan: $(printf '%s ' "${ROMS[@]%%;*}")"
    action="${2:-}"
    extra=""
    shift $(( $# >= 2 ? 2 : 1 ))
    args=("$@")
else
    rom=$(pick_rom) || exit 1
    action=$(pick_action) || exit 1
    interactive=1
fi

IFS=';' read -r key name prefix fallback sname official pattern preset vdef vlist gdef glist <<<"$rom"

# Pilih varian & GApps (hanya untuk perintah yang membuild, dan hanya lewat menu)
chosen=""
if [ "${interactive:-0}" = 1 ] && { [ -z "$action" ] || [ "$action" = build ]; }; then
    vs=(${vlist//,/ })
    echo "${c_in}== Pilih varian ==${c_0}"
    i=1; d=1
    for v in "${vs[@]}"; do
        case "$v" in
            user) label="user (rilis)" ;; userdebug) label="userdebug (debug, adb root)" ;;
            both) label="user + userdebug sekaligus" ;; *) label="$v" ;;
        esac
        [ "$v" = "$vdef" ] && { label="$label  [bawaan]"; d=$i; }
        printf '  %d) %s\n' $i "$label"; i=$((i + 1))
    done
    read -rp "Nomor varian [$d]: " n; n="${n:-$d}"
    [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#vs[@]} ] || die "Pilihan varian tidak ada"
    chosen="VARIANT=${vs[$((n - 1))]}"

    IFS=',' read -ra gs <<<"$glist"
    if [ ${#gs[@]} -gt 1 ]; then
        echo "${c_in}== Pilih GApps / Vanilla ==${c_0}"
        i=1; d=1
        for g in "${gs[@]}"; do
            label="${g#*=}"
            [ "${g%%=*}" = "$gdef" ] && { label="$label  [bawaan]"; d=$i; }
            printf '  %d) %s\n' $i "$label"; i=$((i + 1))
        done
        read -rp "Nomor GApps [$d]: " n; n="${n:-$d}"
        [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#gs[@]} ] || die "Pilihan GApps tidak ada"
        g="${gs[$((n - 1))]%%=*}"
        [ -n "$g" ] && chosen="$chosen GAPPS=$g"
    else
        echo "GApps: ${glist#*=}"
    fi

    echo "Pengaturan tambahan (kosongkan kalau tidak ada), contoh: DECRYPT=0 GOFILE=0"
    read -rp "> " extra
fi

opts=()
for kv in $preset $chosen $extra; do
    [[ "$kv" =~ ^[A-Z_][A-Z0-9_]*=[A-Za-z0-9_./~:-]*$ ]] || die "Pengaturan '$kv' tidak valid (tulis seperti GAPPS=0)"
    [[ "$kv" == *=~/* ]] && kv="${kv%%=*}=$HOME/${kv#*=~/}"
    opts+=("$kv")
done

# ---------------------------------------------- pilih versi ROM otomatis
if [ -n "$prefix" ]; then
    branch=""
    devheads=$(heads "$GH/kingD2N/$DEV")
    if [ -n "$devheads" ]; then
        branch=$(grep "^${prefix}" <<<"$devheads" | while read -r b; do
                     [[ "$BLOCKED" == *" $b "* ]] && continue
                     k=$(verkey "${b#"$prefix"}") && echo "$k $b"
                 done | sort | tail -n 1 | cut -d' ' -f2)
    fi
    [ -n "$branch" ] || branch="$fallback"
    path="$DEV/$branch/$sname"
    echo "${c_in}[..]${c_0} $name: versi device tree terbaru = $branch"

    # Bandingkan dengan source resmi
    if [ -n "$official" ]; then
        top=$(heads "$GH/$official" | grep -E "$pattern" | newest)
        # Branch baru kadang cuma salinan manifest lama (revisi bawaan masih versi
        # sebelumnya, mis. AxionOS lineage-24.0 -> lineage-23.2): pakai revisi aslinya.
        if [ -n "$top" ]; then
            real=$(curl -fsSL "https://raw.githubusercontent.com/$official/$top/default.xml" 2>/dev/null \
                   | grep -oE '<default[^>]*revision="(refs/heads/)?[^"]+"' \
                   | grep -oE 'revision="[^"]+"' | sed -E 's|revision="(refs/heads/)?||; s|"$||' | head -n 1)
            if [ -n "$real" ] && [ "$real" != "$top" ] && grep -qE "$pattern" <<<"$real"; then
                top="$real"
            fi
        fi
        mine=$(verkey "${branch#"$prefix"}" 2>/dev/null || true)
        if [ -n "$top" ] && [ -n "$mine" ]; then
            if [[ "$(verkey "$top")" > "$mine" ]]; then
                echo "${c_wr}[BARU]${c_0} Source resmi $name sudah punya versi lebih baru: branch '$top'."
                echo "       Device tree ingres untuk versi itu belum siap, jadi yang dibuild tetap $branch."
                echo "       Minta dibuatkan dulu (sebut: \"$name rilis $top\")."
            else
                echo "${c_ok}[OK]${c_0} Sudah versi terbaru dari source resmi ($top)."
            fi
        fi
    fi
else
    path="Device_ingres_aospa/main/$sname"
fi

script="$HOME/$sname"
echo "${c_in}[..]${c_0} Unduh script terbaru: $name"
curl -fsSL -o "$script.new" "$RAW/$path?$(date +%s)" || die "Gagal unduh $RAW/$path"
bash -n "$script.new" || die "Script yang diunduh rusak, coba lagi"
mv -f "$script.new" "$script"

echo "${c_ok}[OK]${c_0} bash $script ${action:-(sync + build)} ${args[*]:-} ${opts[*]:-}"
[ "${MENU_DRY:-0}" = 1 ] && { echo "DRY: $path ${action:-} ${args[*]:-}"; exit 0; }
if [ ${#opts[@]} -gt 0 ]; then
    exec env "${opts[@]}" bash "$script" ${action:+"$action"} "${args[@]}"
else
    exec bash "$script" ${action:+"$action"} "${args[@]}"
fi
