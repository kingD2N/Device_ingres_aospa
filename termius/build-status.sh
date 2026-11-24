#!/usr/bin/env bash
# Lihat semua build ROM yang sedang berjalan di akun server ini (sesi byobu/tmux).
#
# Pakai:
#   bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/build-status.sh)
#   bash <(curl -fsSL .../build-status.sh) w          # tampil langsung, segar tiap 10 detik (keluar: ctrl+C)
#   bash <(curl -fsSL .../build-status.sh) lunaris    # detail satu ROM: 15 baris log terakhir
#
# Hanya membaca (sesi, log, proses). Tidak mengubah build apa pun.
set -u

# kunci|nama|file log di $HOME
ROMS=(
    "evox|Evolution X|build-evox.log"
    "los24|LineageOS 24|build.log"
    "pixelos|PixelOS|build-pixelos.log"
    "lunaris|Lunaris|build-lunaris.log"
    "alpha|AlphaDroid|build-alpha.log"
    "axion|AxionOS|build-axion.log"
    "ascp|ASCP|build-ascp.log"
    "infinity|Infinity X|build-infinity.log"
    "uwu|uwuAOSP|build-uwu.log"
    "aospa|AOSPA / PenguinOS|build-aospa.log"
    "crdroid|crDroid|build.log"
    "rros|ResurrectedRemix OS|build.log"
    "derpfest|DerpFest|build-derpfest.log"
    "clover|The Clover Project|build-clover.log"
    "kernel|Kernel ingres|build-kernel.log"
)

c_ok=$'\033[1;32m'; c_wr=$'\033[1;33m'; c_er=$'\033[1;31m'; c_in=$'\033[1;34m'; c_dm=$'\033[2m'; c_0=$'\033[0m'
STRIP='s/\x1b\[[0-9;?]*[a-zA-Z]//g'

dur() {   # detik -> "1j 12m" / "5m" / "30dtk"
    local s=$1
    [ "$s" -lt 0 ] && s=0
    if   [ "$s" -ge 3600 ]; then printf '%dj %dm' $((s / 3600)) $((s % 3600 / 60))
    elif [ "$s" -ge 60 ];   then printf '%dm' $((s / 60))
    else printf '%ddtk' "$s"; fi
}

sessions() {  # "nama dibuat_epoch" per baris
    { tmux list-sessions -F '#{session_name} #{session_created}' 2>/dev/null \
        || byobu list-sessions -F '#{session_name} #{session_created}' 2>/dev/null; } || true
}

procs_has() { pgrep -u "$(id -u)" -f "$1" >/dev/null 2>&1; }

# baris terakhir log yang bermakna (tanpa kode warna / carriage return)
last_line() {
    tail -c 20000 "$1" 2>/dev/null | tr '\r' '\n' | sed "$STRIP" | grep -a -v '^[[:space:]]*$' | tail -n 1 | cut -c1-72
}

show_rom() {  # kunci nama log dibuat_epoch
    local key="$1" name="$2" log="$HOME/$3" created="$4" now age up prog sync phase last
    now=$(date +%s)
    up=$(dur $((now - created)))
    phase="menunggu"; prog=""
    if [ -f "$log" ]; then
        age=$((now - $(stat -c %Y "$log" 2>/dev/null || echo "$now")))
        prog=$(tail -c 200000 "$log" | tr '\r' '\n' | sed "$STRIP" | grep -a -o '\[ *[0-9]*% [0-9]*/[0-9]*\]' | tail -n 1)
        sync=$(tail -c 20000 "$log" | tr '\r' '\n' | sed "$STRIP" | grep -a -o 'Fetching: *[0-9]*% ([0-9/]*)' | tail -n 1)
        last=$(last_line "$log")
    else
        age=-1; last="(log belum ada)"
    fi
    if procs_has 'ninja|soong_ui|soong_build'; then phase="build"
    elif procs_has 'repo (sync|init)|git fetch|git clone'; then phase="sync"
    fi
    if [ "$key" = kernel ]; then   # langkah workflow kernel, mis. "[7/11] Compile Kernel"
        phase=$(tail -c 300000 "$log" 2>/dev/null | sed "$STRIP" | grep -a -o '\[[0-9]*/[0-9]*\] .*' | tail -n 1 | cut -c1-60)
        phase="${phase:-menunggu}"
    fi
    echo "${c_ok}●${c_0} ${c_in}${name}${c_0}  ${c_dm}(sesi '$key', jalan $up)${c_0}"
    echo "   Tahap  : $phase${prog:+  $prog}${sync:+  $sync}"
    if [ "$age" -ge 0 ]; then
        if [ "$age" -gt 900 ] && ! procs_has 'ninja|soong_ui|soong_build|repo sync|git fetch|git clone|ld\.lld|clang'; then
            echo "   Log    : ${c_wr}tidak bergerak $(dur "$age") dan tidak ada proses build/sync (mungkin macet atau menunggu)${c_0}"
        else
            echo "   Log    : diperbarui $(dur "$age") lalu"
        fi
    fi
    echo "   Akhir  : $last"
    if tail -c 30000 "$log" 2>/dev/null | sed "$STRIP" | grep -a -q 'FAILED:\|\[GAGAL\]'; then
        echo "   ${c_er}Ada 'FAILED'/'GAGAL' di log. Lihat: bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/build-status.sh) $key${c_0}"
    fi
    echo
}

report() {
    local snap line key name lg r found=0 other="" shown=" "
    snap=$(sessions)
    echo "${c_in}== Build yang sedang berjalan ($(date '+%d %b %H:%M')) ==${c_0}"
    echo
    while read -r sname created; do
        [ -n "$sname" ] || continue
        for r in "${ROMS[@]}"; do
            IFS='|' read -r key name lg <<<"$r"
            if [ "$sname" = "$key" ]; then
                show_rom "$key" "$name" "$lg" "$created"; found=1; shown="$shown$key "
                continue 2
            fi
        done
        other="$other$sname "
    done <<<"$snap"
    [ "$found" = 1 ] || echo "Tidak ada build ROM yang berjalan di akun ini."$'\n'
    [ -z "$other" ] || echo "${c_dm}Sesi lain: $other${c_0}"$'\n'

    # build yang berhenti dalam 24 jam terakhir (log ada, sesi tidak)
    local seen=" " f age now; now=$(date +%s)
    for r in "${ROMS[@]}"; do
        IFS='|' read -r key name lg <<<"$r"
        case "$shown" in *" $key "*) continue ;; esac
        case "$seen" in *" $lg "*) continue ;; esac
        [ -f "$HOME/$lg" ] || continue
        age=$((now - $(stat -c %Y "$HOME/$lg")))
        [ "$age" -lt 86400 ] || continue
        seen="$seen$lg "
        if [ "$lg" = "build.log" ]; then name="build.log (crDroid/RROS/LineageOS 24)"; fi
        echo "${c_dm}○ $name: tidak berjalan, log terakhir $(dur "$age") lalu${c_0}"
        echo "${c_dm}   $(last_line "$HOME/$lg")${c_0}"
    done

    echo
    printf 'Beban: %s | RAM bebas: %s | Disk bebas: %s\n' \
        "$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)" \
        "$(free -g 2>/dev/null | awk '/^Mem:/ {print $7 " GB"}')" \
        "$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
    echo "${c_dm}Buka layar build: byobu attach -t <sesi>  (keluar: F6)${c_0}"
}

detail() {
    local k="$1" r key name lg
    for r in "${ROMS[@]}"; do
        IFS='|' read -r key name lg <<<"$r"
        [ "$key" = "$k" ] || continue
        echo "${c_in}== $name — 15 baris log terakhir ($HOME/$lg) ==${c_0}"
        [ -f "$HOME/$lg" ] || { echo "Log belum ada."; return; }
        tail -c 30000 "$HOME/$lg" | tr '\r' '\n' | sed "$STRIP" | grep -a -v '^[[:space:]]*$' | tail -n 15 | cut -c1-110
        echo "${c_dm}Buka layar build: byobu attach -t $key  (keluar: F6)${c_0}"
        return
    done
    echo "ROM '$k' tidak dikenal. Pilihan: $(for r in "${ROMS[@]}"; do printf '%s ' "${r%%|*}"; done)"
}

case "${1:-}" in
    w|live)
        while true; do clear; report; echo; echo "${c_dm}Segar tiap 10 detik. Keluar: ctrl+C${c_0}"; sleep 10; done ;;
    "") report ;;
    *)  detail "$1" ;;
esac
