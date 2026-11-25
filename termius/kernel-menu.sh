#!/usr/bin/env bash
#
# Menu build KERNEL ingres (POCO F4 GT) di server lewat Termius.
# Pilihan kernel, branch, KernelSU dan fitur sama persis dengan workflow GitHub
# kingD2N/Kernel_NoMount_ingres (build_ingres.yml) - menu membaca workflow terbaru
# setiap kali dibuka, jadi kernel/fitur/perbaikan baru di workflow langsung ikut.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/kernel-menu.sh)
#
# Langsung tanpa menu utama:
#   bash <(curl -fsSL .../kernel-menu.sh) build     # pilih kernel & fitur, lalu build
#   bash <(curl -fsSL .../kernel-menu.sh) ulang     # build lagi dengan pilihan terakhir
#   bash <(curl -fsSL .../kernel-menu.sh) status    # progres build
#   bash <(curl -fsSL .../kernel-menu.sh) upload    # upload ulang hasil terakhir ke GoFile
#   bash <(curl -fsSL .../kernel-menu.sh) stop      # hentikan build
#   bash <(curl -fsSL .../kernel-menu.sh) bersih    # hapus folder kerja kernel (hemat disk)
#   GOFILE=0 bash <(curl -fsSL .../kernel-menu.sh) build   # tanpa upload GoFile
#
# Build jalan di sesi byobu 'kernel' (aman kalau Termius ditutup), log di ~/build-kernel.log,
# hasil (zip AnyKernel3 + APK manager) di ~/hasil-kernel/<nama>-<tanggal>/ lalu diupload ke GoFile.

set -uo pipefail

RAW=https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius
WF_URL=https://github.com/kingD2N/Kernel_NoMount_ingres
BASE="$HOME/kernel-ingres"
WF="$BASE/workflow"
RUNNER="$WF/termius/kernel_runner.py"
SELF="$HOME/.cache/kernel-ingres/kernel-menu.sh"
CONF="$HOME/.kernel-menu.json"
LOG="$HOME/build-kernel.log"
HASIL="$HOME/hasil-kernel"
SESSION=kernel
# sesi build ROM (lihat build-status.sh) - satu build per akun
ROM_SESSIONS="evox los24 pixelos lunaris alpha axion ascp infinity uwu aospa penguin crdroid rros derpfest clover twrp ofox"

c_ok=$'\e[1;32m'; c_in=$'\e[1;34m'; c_wr=$'\e[1;33m'; c_er=$'\e[1;31m'; c_dm=$'\e[2m'; c_0=$'\e[0m'
ok()   { echo "${c_ok}[OK]${c_0} $*"; }
info() { echo "${c_in}[..]${c_0} $*"; }
warn() { echo "${c_wr}[!!]${c_0} $*"; }
err()  { echo "${c_er}[GAGAL]${c_0} $*" >&2; }
die()  { err "$*"; exit 1; }
STRIP='s/\x1b\[[0-9;?]*[a-zA-Z]//g'

has_session() { { tmux has-session -t "=$1" || byobu has-session -t "=$1"; } >/dev/null 2>&1; }
running_roms() {
    local s out=""
    for s in $ROM_SESSIONS; do has_session "$s" && out="$out $s"; done
    echo "${out# }"
}

# ------------------------------------------------- salinan workflow terbaru
ensure_wf() {
    command -v git >/dev/null || die "git tidak ada di server"
    command -v python3 >/dev/null || die "python3 tidak ada di server"
    mkdir -p "$BASE"
    info "Ambil workflow kernel terbaru ($WF_URL)"
    if [ -d "$WF/.git" ]; then
        GIT_TERMINAL_PROMPT=0 git -C "$WF" fetch -q --depth=1 origin main 2>/dev/null \
            && git -C "$WF" reset -q --hard FETCH_HEAD || need_token
    else
        rm -rf "$WF"
        GIT_TERMINAL_PROMPT=0 git clone -q --depth=1 "$WF_URL" "$WF" 2>/dev/null || need_token
    fi
    [ -f "$RUNNER" ] || die "termius/kernel_runner.py belum ada di repo workflow"
    ok "Workflow: $(git -C "$WF" log -1 --format='%h %s' | cut -c1-70)"
}

need_token() {
    err "Repo workflow kernel (Kernel_NoMount_ingres) privat, server belum boleh membacanya."
    cat <<EOF
Buat token GitHub yang boleh MEMBACA repo itu saja:
  GitHub > Settings > Developer settings > Personal access tokens > Fine-grained tokens > Generate
  Repository access : Only select repositories > Kernel_NoMount_ingres
  Permissions       : Contents = Read-only (izin lain biarkan kosong)
Token ini tetap bisa membaca semua repo publik, jadi sync ROM tetap jalan.
Lalu simpan token di server dengan perintah ini, dan buka menu kernel lagi:
EOF
    echo
    echo "bash <(curl -fsSL $RAW/github-token.sh)"
    echo
    exit 1
}

# ------------------------------------------------------------- GoFile
gofile_put() {   # $1=file $2=folderId(opsional) $3=token(opsional) -> JSON
    local args=(-sS --retry 3 --retry-delay 10 -F "file=@$1")
    [ -n "$2" ] && args+=(-F "folderId=$2")
    [ -n "$3" ] && args+=(-H "Authorization: Bearer $3")
    curl "${args[@]}" https://upload.gofile.io/uploadfile
}

is_ok() {
    python3 -c "import json,sys
try: sys.exit(0 if json.load(sys.stdin).get('status')=='ok' else 1)
except Exception: sys.exit(1)"
}

json_get() {
    python3 -c "import json,sys
try: print(json.load(sys.stdin).get('data',{}).get('$1',''))
except Exception: pass"
}

last_dir() { [ -f "$HASIL/.terakhir" ] && head -n 1 "$HASIL/.terakhir"; }

do_upload() {
    local dir files=() f resp link="" folder="" token="${GOFILE_TOKEN:-}" linkfile page
    dir=$(last_dir)
    [ -n "$dir" ] && [ -d "$dir" ] || { err "Belum ada hasil build kernel di $HASIL"; return 1; }
    linkfile="$dir/link-gofile.txt"
    for f in "$dir"/*.zip "$dir"/*.apk "$dir"/rekernel* "$dir"/info-build.txt "$dir"/sha256.txt; do
        [ -f "$f" ] && files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || { err "Tidak ada file di $dir untuk diupload"; return 1; }
    info "Upload ${#files[@]} file ke GoFile ($(basename "$dir"))"
    : > "$linkfile"
    for f in "${files[@]}"; do
        info "Upload $(basename "$f") ($(du -h "$f" | cut -f1))"
        resp=$(gofile_put "$f" "$folder" "$token")
        echo "$resp" | is_ok || resp=$(gofile_put "$f" "" "${GOFILE_TOKEN:-}")
        if echo "$resp" | is_ok; then
            [ -n "$folder" ] || folder=$(echo "$resp" | json_get parentFolder)
            [ -n "$token" ] || token=$(echo "$resp" | json_get guestToken)
            page=$(echo "$resp" | json_get downloadPage)
            [ -n "$link" ] || link="$page"
            echo "$(basename "$f")  $page" >> "$linkfile"
        else
            err "Gagal upload $(basename "$f"): $(echo "$resp" | head -c 200)"
            echo "$(basename "$f")  GAGAL" >> "$linkfile"
        fi
    done
    echo
    ok "Link GoFile (buka di browser HP untuk download):"
    cat "$linkfile"
    echo "Link juga tersimpan di $linkfile"
}

# ------------------------------------------------------- jalankan build
show_conf() {
    python3 - "$CONF" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
print("  " + "\n  ".join(f"{k:<16} {str(v).lower() if isinstance(v, bool) else v}" for k, v in d.items()))
EOF
}

start_build() {   # pilihan sudah ada di $CONF
    local roms ans
    if has_session "$SESSION"; then
        err "Build kernel masih berjalan (sesi '$SESSION'). Lihat progres dengan perintah status."
        exit 1
    fi
    roms=$(running_roms)
    if [ -n "$roms" ]; then
        warn "Build ROM sedang berjalan di akun ini: $roms (aturan server: satu build per akun)."
        read -rp "Tetap build kernel bersamaan? (y/N): " ans
        [[ "$ans" =~ ^[yY]$ ]] || { info "Batal. Pilihanmu tersimpan, jalankan lagi dengan menu 2 (ulangi build terakhir)."; exit 0; }
    fi
    mkdir -p "$(dirname "$SELF")"
    if [[ "$0" == /dev/fd/* || "$0" == /proc/* || ! -f "$0" ]]; then
        curl -fsSL -o "$SELF.new" "$RAW/kernel-menu.sh?$(date +%s)" || die "Gagal unduh kernel-menu.sh"
    else
        cp -f "$0" "$SELF.new"
    fi
    bash -n "$SELF.new" || die "kernel-menu.sh yang diunduh rusak, coba lagi"
    mv -f "$SELF.new" "$SELF"

    [ "${MENU_DRY:-0}" = 1 ] && { echo "DRY: bash $SELF _run"; exit 0; }
    local envs="GOFILE='${GOFILE:-1}' GOFILE_TOKEN='${GOFILE_TOKEN:-}' KERNEL_JOBS='${KERNEL_JOBS:-}'"
    if [ -n "${TMUX:-}" ] || [ -n "${STY:-}" ]; then
        exec env GOFILE="${GOFILE:-1}" GOFILE_TOKEN="${GOFILE_TOKEN:-}" KERNEL_JOBS="${KERNEL_JOBS:-}" bash "$SELF" _run
    fi
    command -v byobu >/dev/null || die "byobu tidak ada di server"
    byobu new-session -d -s "$SESSION" "$envs bash '$SELF' _run; echo; echo 'Selesai. Tekan Enter untuk menutup.'; read" \
        || die "Gagal membuat sesi byobu '$SESSION'"
    ok "Build kernel berjalan di sesi byobu '$SESSION' (aman kalau Termius ditutup)."
    echo "   Lihat layar build : byobu attach -t $SESSION   (keluar lagi: F6)"
    echo "   Cek progres saja  :"
    echo
    echo "bash <(curl -fsSL $RAW/kernel-menu.sh) status"
    echo
}

run_inside() {    # di dalam sesi byobu
    local rc
    : > "$LOG"
    {
        echo "=== Build kernel ingres mulai $(date '+%d %b %Y %H:%M') ==="
        python3 -u "$RUNNER" build --repo "$WF" --inputs "$CONF"
    } 2>&1 | tee -a "$LOG"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then
        echo "${c_er}[GAGAL]${c_0} Build kernel berhenti. Kirim file ~/build-kernel.log untuk diperbaiki." | tee -a "$LOG"
        exit "$rc"
    fi
    if [ "${GOFILE:-1}" = 1 ]; then
        do_upload 2>&1 | tee -a "$LOG"
    else
        info "GOFILE=0: hasil tidak diupload. Upload nanti dengan perintah upload." | tee -a "$LOG"
    fi
}

# ------------------------------------------------------------------ status
do_status() {
    local step last dir now age
    echo "${c_in}== Build kernel ingres ==${c_0}"
    if has_session "$SESSION"; then
        echo "${c_ok}●${c_0} BERJALAN (sesi '$SESSION')"
    else
        echo "${c_dm}○ tidak berjalan${c_0}"
    fi
    if [ -f "$LOG" ]; then
        now=$(date +%s); age=$(( now - $(stat -c %Y "$LOG") ))
        step=$(sed "$STRIP" "$LOG" | grep -a '▶ \[' | tail -n 1 | sed 's/^▶ //')
        last=$(tail -c 20000 "$LOG" | tr '\r' '\n' | sed "$STRIP" | grep -a -v '^[[:space:]]*$' | tail -n 1 | cut -c1-90)
        echo "   Langkah : ${step:-belum mulai}"
        echo "   Log     : diperbarui $((age / 60)) menit lalu (~/build-kernel.log)"
        echo "   Akhir   : $last"
        if sed "$STRIP" "$LOG" | grep -a -q '\[GAGAL\]'; then
            echo "   ${c_er}Ada [GAGAL] di log:${c_0}"
            sed "$STRIP" "$LOG" | grep -a '\[GAGAL\]\|error:\|Error [0-9]' | tail -n 5 | cut -c1-110 | sed 's/^/     /'
        fi
    else
        echo "   Log belum ada."
    fi
    dir=$(last_dir)
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        echo
        echo "${c_in}Hasil terakhir:${c_0} $dir"
        if [ -s "$dir/link-gofile.txt" ]; then sed 's/^/   /' "$dir/link-gofile.txt"
        else ls -1 "$dir" | sed 's/^/   /'; fi
    fi
    printf '\nDisk bebas: %s\n' "$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
}

do_stop() {
    has_session "$SESSION" || { info "Tidak ada build kernel yang berjalan."; return 0; }
    local ans
    read -rp "Hentikan build kernel yang sedang berjalan? (y/N): " ans
    [[ "$ans" =~ ^[yY]$ ]] || { info "Batal."; return 0; }
    byobu kill-session -t "$SESSION" >/dev/null 2>&1 || tmux kill-session -t "$SESSION" >/dev/null 2>&1
    ok "Build kernel dihentikan."
}

do_bersih() {
    has_session "$SESSION" && die "Build kernel masih berjalan - hentikan dulu (perintah stop)."
    echo "Yang akan DIHAPUS:"
    echo "   $BASE                      (source kernel, LLVM, folder kerja)  $(du -sh "$BASE" 2>/dev/null | cut -f1)"
    echo "   ~/.cache/kernel-ingres/dl  (unduhan LLVM / NDK)                  $(du -sh "$HOME/.cache/kernel-ingres/dl" 2>/dev/null | cut -f1)"
    echo "Hasil kernel di $HASIL TIDAK dihapus."
    local ans
    read -rp "Ketik YA lalu Enter untuk menghapus: " ans
    [ "$ans" = YA ] || { info "Batal, tidak ada yang dihapus."; return 0; }
    rm -rf "$BASE" "$HOME/.cache/kernel-ingres/dl"
    read -rp "Hapus juga ccache kernel (~/.ccache_ingres, $(du -sh "$HOME/.ccache_ingres" 2>/dev/null | cut -f1); build berikutnya lebih lama)? (y/N): " ans
    [[ "$ans" =~ ^[yY]$ ]] && rm -rf "$HOME/.ccache_ingres" && ok "ccache dihapus"
    ok "Selesai. Disk bebas: $(df -h "$HOME" | awk 'NR==2 {print $4}')"
}

not_running() {
    has_session "$SESSION" && die "Build kernel masih berjalan (sesi '$SESSION'). Lihat progres dengan perintah status."
    return 0
}

cmd_build() {
    not_running
    ensure_wf
    python3 "$RUNNER" menu --repo "$WF" --out "$CONF.new"
    case $? in
        0) mv -f "$CONF.new" "$CONF"; start_build ;;
        3) mv -f "$CONF.new" "$CONF"; exit 0 ;;
        *) rm -f "$CONF.new"; die "Menu pilihan gagal" ;;
    esac
}

cmd_ulang() {
    [ -f "$CONF" ] || die "Belum ada pilihan build sebelumnya - pilih dulu lewat menu 1."
    not_running
    ensure_wf
    echo "${c_in}== Pilihan build terakhir ==${c_0}"
    show_conf
    local ans
    read -rp "Build dengan pilihan ini? (Y/n): " ans
    [[ "$ans" =~ ^[nN]$ ]] && { info "Batal."; exit 0; }
    start_build
}

main_menu() {
    local n last=""
    [ -f "$CONF" ] && last=$(python3 -c "import json;d=json.load(open('$CONF'));print(' '.join(x for x in (d.get('kernel_source',''), d.get('ksu_type','')) if x))" 2>/dev/null)
    echo "${c_in}== Build kernel ingres (POCO F4 GT) ==${c_0}"
    echo "  1) Build kernel baru (pilih kernel, KernelSU & fitur)"
    echo "  2) Ulangi build terakhir${last:+ ${c_dm}($last)${c_0}}"
    echo "  3) Lihat progres build"
    echo "  4) Upload ulang hasil terakhir ke GoFile"
    echo "  5) Hentikan build yang sedang berjalan"
    echo "  6) Hapus folder kerja kernel (hemat disk)"
    echo "  0) Keluar"
    read -rp "Nomor [1]: " n
    case "${n:-1}" in
        1) cmd_build ;;
        2) cmd_ulang ;;
        3) do_status ;;
        4) do_upload ;;
        5) do_stop ;;
        6) do_bersih ;;
        0) exit 0 ;;
        *) die "Pilihan tidak ada" ;;
    esac
}

case "${1:-}" in
    "")            main_menu ;;
    build|baru)    cmd_build ;;
    ulang|lagi)    cmd_ulang ;;
    status|cek)    do_status ;;
    upload)        do_upload ;;
    stop|berhenti) do_stop ;;
    bersih|clean)  do_bersih ;;
    _run)          run_inside ;;
    *) die "Perintah '$1' tidak dikenal. Pilihan: build ulang status upload stop bersih" ;;
esac
