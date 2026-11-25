#!/usr/bin/env bash
#
# Build TWRP (Recovery Project™) untuk ingres (POCO F4 GT) di server lewat Termius.
# Isi sama dengan workflow GitHub kingD2N/TWRP-PROJECT- ("Recovery Build"):
#   manifest minimal TWRP (twrp-12.1) + device tree kingD2N/device_xiaomi_ingres-TWRP (main),
#   nama "Team Win Recovery Project" diganti "Recovery Project™",
#   lunch twrp_ingres-eng, mka adbd recoveryimage.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/twrp-menu.sh)
#
#   ... twrp-menu.sh build     # build (source dipakai lagi kalau sudah ada)
#   ... twrp-menu.sh sync      # sync ulang source TWRP lalu build
#   ... twrp-menu.sh status    # progres build
#   ... twrp-menu.sh upload    # upload ulang hasil terakhir ke GoFile
#   ... twrp-menu.sh stop      # hentikan build
#   ... twrp-menu.sh bersih    # hapus source TWRP (hemat disk)
#
# Pengaturan (tulis di depan perintah): MANIFEST_BRANCH=twrp-12.1  TREE_BRANCH=main  GOFILE=0  JOBS=16
# Build jalan di sesi byobu 'twrp' (aman kalau Termius ditutup), log ~/build-twrp.log,
# hasil di ~/hasil-twrp/<tanggal>/ lalu diupload ke GoFile.

set -uo pipefail

RAW=https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius
MANIFEST_URL=https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git
MANIFEST_BRANCH="${MANIFEST_BRANCH:-twrp-12.1}"
TREE_URL=https://github.com/kingD2N/device_xiaomi_ingres-TWRP
TREE_BRANCH="${TREE_BRANCH:-main}"
DEVICE_PATH=device/xiaomi/ingres
PRODUCT=twrp_ingres
WORK="$HOME/twrp-ingres"
SRC="$WORK/$MANIFEST_BRANCH"
HASIL="$HOME/hasil-twrp"
LOG="$HOME/build-twrp.log"
SELF="$HOME/.cache/twrp-ingres/twrp-menu.sh"
SESSION=twrp

c_ok=$'\e[1;32m'; c_in=$'\e[1;34m'; c_wr=$'\e[1;33m'; c_er=$'\e[1;31m'; c_0=$'\e[0m'
ok()   { echo "${c_ok}[OK]${c_0} $*"; }
info() { echo "${c_in}[..]${c_0} $*"; }
warn() { echo "${c_wr}[!!]${c_0} $*"; }
err()  { echo "${c_er}[GAGAL]${c_0} $*" >&2; }
die()  { err "$*"; exit 1; }
STRIP='s/\x1b\[[0-9;?]*[a-zA-Z]//g'

has_session() { { tmux has-session -t "=$1" || byobu has-session -t "=$1"; } >/dev/null 2>&1; }
last_dir() { [ -f "$HASIL/.terakhir" ] && head -n 1 "$HASIL/.terakhir"; }

# ------------------------------------------------------------------ GoFile
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
do_upload() {
    local dir files=() f resp folder="" token="${GOFILE_TOKEN:-}" linkfile page
    dir=$(last_dir)
    [ -n "$dir" ] && [ -d "$dir" ] || { err "Belum ada hasil build TWRP di $HASIL"; return 1; }
    linkfile="$dir/link-gofile.txt"
    for f in "$dir"/*.img "$dir"/*.zip "$dir"/info-build.txt; do
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
            echo "$(basename "$f")  $page" >> "$linkfile"
        else
            err "Gagal upload $(basename "$f"): $(echo "$resp" | head -c 200)"
            echo "$(basename "$f")  GAGAL" >> "$linkfile"
        fi
    done
    echo
    ok "Link GoFile (buka di browser HP untuk download):"
    cat "$linkfile"
}

# ------------------------------------------------------------------ build (di dalam sesi byobu)
ensure_repo() {
    command -v repo >/dev/null && return 0
    [ -x "$HOME/bin/repo" ] || { mkdir -p "$HOME/bin" && curl -fsSL -o "$HOME/bin/repo" https://storage.googleapis.com/git-repo-downloads/repo && chmod +x "$HOME/bin/repo"; } \
        || die "Gagal mengunduh alat repo"
    export PATH="$HOME/bin:$PATH"
}

do_sync() {
    local i
    ensure_repo
    git config --global user.name >/dev/null 2>&1 || git config --global user.name kingD2N
    git config --global user.email >/dev/null 2>&1 || git config --global user.email "114895723+kingD2N@users.noreply.github.com"
    mkdir -p "$SRC" && cd "$SRC" || die "Tidak bisa masuk $SRC"
    if [ ! -d .repo ]; then
        info "repo init $MANIFEST_BRANCH (manifest minimal TWRP)"
        repo init --depth=1 -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" || die "repo init gagal"
    fi
    for i in 1 2 3; do
        info "repo sync (percobaan $i/3)"
        repo sync -c --no-clone-bundle --no-tags --force-sync -j"$JOBS" && { ok "Sync selesai"; return 0; }
        warn "repo sync gagal, coba lagi"
        sleep 20
    done
    die "repo sync gagal 3x. Cek koneksi/ruang disk lalu coba: bash <(curl -fsSL $RAW/twrp-menu.sh) sync"
}

run_inside() {
    local t0 out stamp dir rc img
    t0=$(date +%s)
    JOBS="${JOBS:-$(nproc --all)}"
    echo "=== Build TWRP ingres mulai $(date '+%d %b %Y %H:%M') | $MANIFEST_BRANCH | tree $TREE_BRANCH | -j$JOBS ==="
    df -h "$HOME" | tail -n 1
    if [ "${RESYNC:-0}" = 1 ] || [ ! -f "$SRC/build/envsetup.sh" ]; then
        do_sync
    else
        info "Pakai source TWRP yang sudah ada ($SRC). Sync ulang: perintah 'sync'"
    fi
    cd "$SRC" || die "Source TWRP tidak ada di $SRC"

    info "Device tree $TREE_URL ($TREE_BRANCH)"
    rm -rf "$DEVICE_PATH"
    git clone -q --depth=1 -b "$TREE_BRANCH" "$TREE_URL" "$DEVICE_PATH" || die "Gagal clone device tree"
    ok "Device tree: $(git -C "$DEVICE_PATH" log -1 --format='%h %s' | cut -c1-70)"

    # sama dengan workflow: nama di GUI TWRP diganti (string ada di bootable/recovery)
    if grep -rlq "Team Win Recovery Project" bootable/recovery/ 2>/dev/null; then
        grep -rl "Team Win Recovery Project" bootable/recovery/ | xargs sed -i 's/Team Win Recovery Project/Recovery Project™/g'
        ok "Nama TWRP diganti \"Recovery Project™\""
    fi

    info "Build recovery.img (lunch $PRODUCT-eng)"
    set +u
    # shellcheck disable=SC1091
    source build/envsetup.sh >/dev/null
    export ALLOW_MISSING_DEPENDENCIES=true LC_ALL=C
    lunch "$PRODUCT-eng" || die "lunch $PRODUCT-eng gagal"
    mka adbd recoveryimage -j"$JOBS"
    rc=$?
    set -u
    out="out/target/product/ingres"
    img="$out/recovery.img"
    if [ "$rc" -ne 0 ] || [ ! -f "$img" ]; then
        err "Build TWRP gagal. Penyebab (kirim screenshot ini):"
        grep -a -n -A10 '^FAILED: ' "$LOG" 2>/dev/null | head -n 30
        grep -a -n -E 'error:|ninja: build stopped' "$LOG" 2>/dev/null | tail -n 10
        exit 1
    fi
    stamp=$(date +%Y%m%d_%H%M)
    dir="$HASIL/twrp-ingres-$stamp"
    mkdir -p "$dir"
    cp -f "$img" "$dir/twrp-ingres-$stamp.img"
    for f in "$out"/*.zip; do [ -f "$f" ] && cp -f "$f" "$dir/"; done
    {
        echo "Recovery    : Recovery Project™ (TWRP) ingres"
        echo "Manifest    : $MANIFEST_BRANCH ($MANIFEST_URL)"
        echo "Device tree : $TREE_URL @ $TREE_BRANCH ($(git -C "$DEVICE_PATH" log -1 --format='%h'))"
        echo "Dibuat      : $(date '+%Y-%m-%d %H:%M %Z') di server ($(uname -n))"
    } > "$dir/info-build.txt"
    (cd "$dir" && sha256sum ./*.img > sha256.txt)
    echo "$dir" > "$HASIL/.terakhir"
    ok "TWRP selesai dalam $(( ($(date +%s) - t0) / 60 )) menit. Hasil: $dir"
    ls -lh "$dir"
    if [ "${GOFILE:-1}" = 1 ]; then
        do_upload
    else
        info "GOFILE=0: tidak diupload. Ambil lewat SFTP, atau upload nanti dengan perintah upload."
    fi
}

# ------------------------------------------------------------------ perintah
start_build() {
    if has_session "$SESSION"; then
        err "Build TWRP masih berjalan (sesi '$SESSION'). Lihat: byobu attach -t $SESSION"
        exit 1
    fi
    command -v python3 >/dev/null || die "python3 tidak ada di server"
    mkdir -p "$(dirname "$SELF")"
    if [[ "$0" == /dev/fd/* || "$0" == /proc/* || ! -f "$0" ]]; then
        curl -fsSL -o "$SELF.new" "$RAW/twrp-menu.sh?$(date +%s)" || die "Gagal unduh twrp-menu.sh"
    else
        cp -f "$0" "$SELF.new"
    fi
    bash -n "$SELF.new" || die "twrp-menu.sh yang diunduh rusak, coba lagi"
    mv -f "$SELF.new" "$SELF"
    [ "${MENU_DRY:-0}" = 1 ] && { echo "DRY: RESYNC=${RESYNC:-0} bash $SELF _run"; exit 0; }
    local envs="RESYNC='${RESYNC:-0}' MANIFEST_BRANCH='$MANIFEST_BRANCH' TREE_BRANCH='$TREE_BRANCH' GOFILE='${GOFILE:-1}' GOFILE_TOKEN='${GOFILE_TOKEN:-}' JOBS='${JOBS:-}'"
    if [ -n "${TMUX:-}" ] || [ -n "${STY:-}" ]; then
        eval "exec env $envs bash \"\$SELF\" _run"
    fi
    command -v byobu >/dev/null || die "byobu tidak ada di server"
    byobu new-session -d -s "$SESSION" "$envs bash '$SELF' _run; echo; echo 'Selesai. Tekan Enter untuk menutup.'; read" \
        || die "Gagal membuat sesi byobu '$SESSION'"
    ok "Build TWRP berjalan di sesi byobu '$SESSION' (aman kalau Termius ditutup)."
    echo "   Lihat layar build : byobu attach -t $SESSION   (keluar lagi: F6)"
    echo "   Cek progres saja  :"
    echo
    echo "bash <(curl -fsSL $RAW/twrp-menu.sh) status"
    echo
}

do_status() {
    local dir
    echo "${c_in}== Build TWRP ingres ==${c_0}"
    if has_session "$SESSION"; then echo "${c_ok}●${c_0} BERJALAN (sesi '$SESSION')"; else echo "○ tidak berjalan"; fi
    if [ -f "$LOG" ]; then
        echo "   Akhir log : $(tail -c 20000 "$LOG" | tr '\r' '\n' | sed "$STRIP" | grep -a -v '^[[:space:]]*$' | tail -n 1 | cut -c1-90)"
        sed "$STRIP" "$LOG" | grep -a -q '\[GAGAL\]' && sed "$STRIP" "$LOG" | grep -a '\[GAGAL\]' | tail -n 3 | sed 's/^/   /'
    fi
    dir=$(last_dir)
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        echo "   Hasil terakhir: $dir"
        ls -1 "$dir" | sed 's/^/     - /'
    fi
}

do_stop() {
    has_session "$SESSION" || { info "Tidak ada build TWRP yang berjalan."; return 0; }
    byobu kill-session -t "$SESSION" 2>/dev/null || tmux kill-session -t "$SESSION"
    ok "Build TWRP dihentikan."
}

do_bersih() {
    has_session "$SESSION" && die "Build TWRP masih berjalan, hentikan dulu (stop)."
    [ -d "$WORK" ] || { info "Tidak ada source TWRP di $WORK"; return 0; }
    echo "Hapus source TWRP $WORK ($(du -sh "$WORK" 2>/dev/null | cut -f1))? Hasil di $HASIL tetap aman."
    read -rp "Ketik YA untuk menghapus: " a
    [ "$a" = YA ] || { echo "Batal."; return 0; }
    rm -rf "$WORK" && ok "Source TWRP dihapus."
}

case "${1:-build}" in
    _run)            run_inside 2>&1 | tee "$LOG"; exit "${PIPESTATUS[0]}" ;;
    build|baru)      start_build ;;
    sync|ulang)      RESYNC=1 start_build ;;
    status|cek)      do_status ;;
    upload)          do_upload ;;
    stop|berhenti)   do_stop ;;
    bersih|clean)    do_bersih ;;
    *) die "Perintah tidak dikenal: $1 (build, sync, status, upload, stop, bersih)" ;;
esac
