#!/usr/bin/env bash
#
# Build ROM Android 17 untuk POCO F4 GT (ingres) - satu perintah.
#   ROM=aospa   (default) Paranoid Android calcite
#   ROM=penguin           PenguinOS celerity (turunan AOSPA calcite)
# Kedua ROM memakai satu folder source yang sama (~/aospa), sesuai aturan
# server "1 source ROM per akun"; pindah ROM cukup sync ulang.
#
#   bash build-aospa.sh            # sync + build (otomatis jalan di byobu)
#   bash build-aospa.sh sync       # hanya sync source
#   bash build-aospa.sh build      # hanya build (lanjut dari build sebelumnya)
#   bash build-aospa.sh clean      # hapus hasil build lama (out/) lalu berhenti
#   bash build-aospa.sh status     # lihat progres build yang sedang jalan
#   bash build-aospa.sh bersih     # hapus source/hasil ROM lama (LineageOS dll) agar disk lega
#   bash build-aospa.sh bersih ~/folderlain   # sekalian hapus folder lain yang disebut
#   bash build-aospa.sh upload     # upload ulang isi ~/hasil-aospa ke GoFile
#   bash build-aospa.sh reset-ingres   # hapus repo ingres/xiaomi lama di source lalu sync ulang
#
# Pengaturan (opsional, isi sebelum perintah, contoh: JOBS=8 bash build-aospa.sh):
#   ROM=penguin        pilih ROM: aospa (default) / penguin
#   SRC=~/aospa        folder source (dipakai bersama semua ROM)
#   JOBS=<angka>       jumlah job build (default: otomatis dari CPU & RAM)
#   VARIANT=user       user (rilis, default) / userdebug (debug, adb root) / eng
#   GOFILE=0           jangan upload hasil ke GoFile (default: upload otomatis)
#   GOFILE_TOKEN=xxx   token akun GoFile (opsional, agar file masuk ke akun sendiri)

set -uo pipefail

ROM="${ROM:-aospa}"
SRC="${SRC:-$HOME/aospa}"
VARIANT="${VARIANT:-user}"
SESSION="aospa"
LOG="$HOME/build-aospa.log"
RAW="https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main"
case "$ROM" in
    aospa)
        ROM_NAME="AOSPA calcite"
        ROM_MANIFEST="https://github.com/AOSPA/manifest"; ROM_BRANCH="calcite"
        MANIFEST_URL="$RAW/local_manifests/ingres.xml" ;;
    penguin|pinguin|penguinos)
        ROM=penguin; ROM_NAME="PenguinOS celerity"
        ROM_MANIFEST="https://github.com/Project-PenguinOS/manifest"; ROM_BRANCH="celerity"
        MANIFEST_URL="$RAW/local_manifests/ingres-penguin.xml" ;;
    *) echo "ROM tidak dikenal: $ROM (pakai aospa / penguin)" >&2; exit 1 ;;
esac
HASIL_DIR="$HOME/hasil-$ROM"
SCRIPT="$(readlink -f "$0")"
CMD="${1:-all}"

ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
info() { echo -e "\033[1;34m[..]\033[0m $*"; }
err()  { echo -e "\033[1;31m[GAGAL]\033[0m $*" >&2; }

# ---------------------------------------------------------------- status
if [ "$CMD" = "status" ]; then
    if [ -f "$LOG" ]; then
        grep -o '\[ *[0-9]*% [0-9]*/[0-9]*\]' "$LOG" | tail -n 1
        tail -n 3 "$LOG"
    else
        echo "Belum ada build.log"
    fi
    byobu ls 2>/dev/null | grep -q "^$SESSION" && echo "Sesi byobu '$SESSION' masih berjalan." \
        || echo "Tidak ada sesi byobu '$SESSION'."
    exit 0
fi

# ------------------------------------------------- bersihkan server
if [ "$CMD" = "bersih" ]; then
    shift
    echo "Ruang disk sekarang:"
    df -h "$HOME" | tail -n 1
    echo
    echo "Isi folder home (terbesar dulu):"
    du -sh "$HOME"/* "$HOME"/.ccache "$HOME"/.cache 2>/dev/null | sort -rh | head -n 15
    echo
    targets=""
    for d in "$HOME/los24" "$HOME/hasil-los24" "$HOME/build.log" "$HOME/.ccache" "$@"; do
        [ -e "$d" ] || continue
        case "$(readlink -f "$d")" in
            "$(readlink -f "$HOME")"|"$(readlink -f "$SRC")"|"$SCRIPT") echo "Lewati $d (tidak boleh dihapus)"; continue ;;
        esac
        targets="$targets $d"
    done
    if [ -z "$targets" ]; then
        ok "Tidak ada folder lama untuk dihapus."
        exit 0
    fi
    echo "Yang akan DIHAPUS PERMANEN:"
    for d in $targets; do echo "   $d"; done
    echo "Simpan dulu zip ROM lama (mis. ~/hasil-los24) lewat SFTP kalau masih perlu."
    read -r -p "Ketik YA lalu Enter untuk menghapus: " jawab
    [ "$jawab" = "YA" ] || { info "Batal, tidak ada yang dihapus."; exit 0; }
    for s in los24 penguin aospa; do
        [ "$s" = "$SESSION" ] && [ -n "${TMUX:-}" ] && continue
        byobu kill-session -t "$s" >/dev/null 2>&1 && info "Sesi byobu '$s' dihentikan"
    done
    info "Menghapus... (bisa 5-20 menit, jangan tutup Termius)"
    # shellcheck disable=SC2086
    rm -rf $targets
    ok "Selesai. Ruang disk sekarang:"
    df -h "$HOME" | tail -n 1
    exit 0
fi

# ------------------------------------------- selalu jalan di dalam byobu
if [ -z "${TMUX:-}" ] && [ -z "${STY:-}" ] && [ "$CMD" != "clean" ] && [ "$CMD" != "reset-ingres" ]; then
    command -v byobu >/dev/null || { err "byobu tidak ada di server"; exit 1; }
    if byobu ls 2>/dev/null | grep -q "^$SESSION"; then
        err "Sesi '$SESSION' sudah ada (satu build per akun). Masuk dengan: byobu attach -t $SESSION"
        exit 1
    fi
    envs="ROM='$ROM' SRC='$SRC' VARIANT='$VARIANT' GOFILE='${GOFILE:-1}' GOFILE_TOKEN='${GOFILE_TOKEN:-}' JOBS='${JOBS:-}'"
    byobu new-session -d -s "$SESSION" "$envs bash '$SCRIPT' $CMD; echo; echo 'Selesai. Tekan Enter untuk menutup.'; read"
    ok "Build berjalan di sesi byobu '$SESSION' (aman kalau Termius ditutup)."
    echo "   Lihat layar build : byobu attach -t $SESSION   (keluar lagi: F6)"
    echo "   Cek progres saja  : bash $SCRIPT status"
    exit 0
fi

# ------------------------------------------------------------- persiapan
check_tools() {
    local miss=""
    for t in git git-lfs python3 curl ccache zip; do command -v "$t" >/dev/null || miss="$miss $t"; done
    if ! command -v repo >/dev/null; then
        info "Memasang repo ke ~/bin"
        mkdir -p "$HOME/bin"
        curl -s https://storage.googleapis.com/git-repo-downloads/repo > "$HOME/bin/repo" && chmod a+x "$HOME/bin/repo"
        export PATH="$HOME/bin:$PATH"
    fi
    [ -z "$miss" ] || { err "Alat belum terpasang di server:$miss (minta pemilik server memasangnya)"; exit 1; }
    git config --global user.name >/dev/null || git config --global user.name "kingD2N"
    git config --global user.email >/dev/null || git config --global user.email "114895723+kingD2N@users.noreply.github.com"
    git lfs install >/dev/null 2>&1 || true
    CCACHE_EXEC="$(command -v ccache)"
    export USE_CCACHE=1 CCACHE_EXEC CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
    ccache -M 50G >/dev/null 2>&1 || true
}

check_disk() {
    local need_gb=$1 avail_gb
    [ "${SKIP_DISK_CHECK:-0}" = 1 ] && return 0
    avail_gb=$(df -BG --output=avail "$HOME" | tail -n 1 | tr -dc '0-9')
    info "Ruang disk kosong: ${avail_gb} GB"
    if [ "${avail_gb:-0}" -lt "$need_gb" ]; then
        err "Ruang disk kurang dari ${need_gb} GB. Hapus build lama: bash $SCRIPT clean"
        exit 1
    fi
}

# ------------------------------------------------- tambalan source
# vendor/xiaomi/sm8450-common (ThankYouMario calcite) meng-import namespace
# hardware/qcom/display* yang tidak ada di display HAL AOSPA calcite-8450
# (modulnya ada di root namespace) -> soong gagal. Buang import itu.
VCOMMON_BP="vendor/xiaomi/sm8450-common/Android.bp"
# folder device/vendor/kernel xiaomi sisa percobaan lama (tidak ada di manifest)
# tetap dibaca soong -> modul ganda ("multiple rules generate ..."). Pindahkan.
move_leftovers() {
    local known d bak="$HOME/aospa-sisa-lama"
    known=$(repo list -p 2>/dev/null) || return 0
    [ -n "$known" ] || return 0
    for d in device/xiaomi/* vendor/xiaomi/* kernel/xiaomi/* hardware/xiaomi*; do
        [ -d "$d" ] || continue
        echo "$known" | grep -qx "$d" && continue
        # folder induk dari repo lain (mis. vendor/xiaomi/camera/...) jangan disentuh
        echo "$known" | grep -q "^$d/" && continue
        mkdir -p "$bak/$(dirname "$d")"
        info "Memindahkan folder sisa lama: $d -> $bak/$d"
        rm -rf "${bak:?}/$d"
        mv "$d" "$bak/$d"
    done
}

unpatch_source() {
    git -C vendor/xiaomi/sm8450-common checkout -q -- Android.bp 2>/dev/null || true
    git -C vendor/qcom/common checkout -q -- . 2>/dev/null || true
}

# Prebuilt "X_xiaomi" (stem X, overrides X) dan prebuilt "X" dari vendor/qcom/common
# sama-sama menyalin symbols/vendor/.../X -> ninja "multiple rules generate".
# Tandai modul qcom yang sudah di-override sebagai installable: false.
fix_overridden_prebuilts() {
    python3 - <<'PYEOF'
import glob, re
over = set()
for bp in ["vendor/xiaomi/sm8450-common/Android.bp", "vendor/xiaomi/ingres/Android.bp"]:
    try:
        txt = open(bp).read()
    except OSError:
        continue
    for blk in re.split(r"\n(?=\w+ \{)", txt):
        m = re.search(r'overrides: \[\s*"([^"]+)"', blk)
        if m and "stem:" in blk:
            over.add(m.group(1))
for bp in glob.glob("vendor/qcom/common/**/Android.bp", recursive=True):
    txt = open(bp).read()
    blocks = re.split(r"\n(?=\w+ \{)", txt)
    changed = False
    for i, blk in enumerate(blocks):
        m = re.search(r'\n    name: "([^"]+)",', blk)
        if m and m.group(1) in over and "installable: false" not in blk:
            blocks[i] = blk.replace(m.group(0), m.group(0) + "\n    installable: false,", 1)
            changed = True
            print("[..] Tambalan: %s di %s -> installable: false" % (m.group(1), bp))
    if changed:
        open(bp, "w").write("\n".join(blocks))
PYEOF
}
patch_source() {
    # link health_product.mk tertinggal setelah healthd-ext dibuang dari manifest
    if [ ! -d vendor/qcom/opensource/healthd-ext ] && [ -L vendor/qcom/defs/product-defs/vendor/health_product.mk ]; then
        rm -f vendor/qcom/defs/product-defs/vendor/health_product.mk
    fi
    fix_overridden_prebuilts
    if [ -f "$VCOMMON_BP" ] && grep -q '"hardware/qcom/display' "$VCOMMON_BP"; then
        sed -i '/^ *"hardware\/qcom\/display/d' "$VCOMMON_BP"
        info "Tambalan: import hardware/qcom/display dibuang dari $VCOMMON_BP"
    fi
}

# ------------------------------------------------------------------ sync
do_sync() {
    mkdir -p "$SRC" && cd "$SRC" || exit 1
    local cur_url cur_branch
    cur_url=$(git -C .repo/manifests config remote.origin.url 2>/dev/null || true)
    cur_branch=$(git -C .repo/manifests config branch.default.merge 2>/dev/null | sed 's#refs/heads/##' || true)
    if [ ! -d .repo ]; then
        check_disk 300
        info "repo init $ROM_NAME"
        repo init -u "$ROM_MANIFEST" -b "$ROM_BRANCH" \
            --git-lfs --no-clone-bundle --depth=1 || { err "repo init gagal"; exit 1; }
    elif [ "${cur_url%.git}" != "$ROM_MANIFEST" ] || { [ -n "$cur_branch" ] && [ "$cur_branch" != "$ROM_BRANCH" ]; }; then
        info "Pindah manifest ke $ROM_NAME (source yang sama dipakai ulang)"
        repo init -u "$ROM_MANIFEST" -b "$ROM_BRANCH" \
            --git-lfs --no-clone-bundle --depth=1 || { err "repo init gagal"; exit 1; }
    fi
    mkdir -p .repo/local_manifests
    # local manifest lama (percobaan sebelumnya) bisa bentrok, singkirkan
    for f in .repo/local_manifests/*.xml; do
        [ -e "$f" ] && [ "$(basename "$f")" != ingres.xml ] && mv -f "$f" "$f.bak" && info "Menyingkirkan $(basename "$f")"
    done
    curl -fsSL -o .repo/local_manifests/ingres.xml "$MANIFEST_URL" || { err "Gagal unduh local manifest"; exit 1; }

    # sisa percobaan lama: folder ingres/xiaomi yang bukan hasil repo ini bikin
    # "unsupported checkout state" dan Android.bp lama (vendor common salah versi)
    reset_project() {
        local rel="${1#"$SRC"/}"; rel="${rel%/.git}"; rel="${rel%/}"
        case "$rel" in ""|/*|*..*) return ;; esac
        info "Menghapus checkout lama: $rel"
        rm -rf "${SRC:?}/$rel" "${SRC:?}/.repo/projects/$rel.git"
    }

    unpatch_source
    local n slog="$HOME/sync-aospa.log"
    for n in 1 2 3; do
        info "repo sync (percobaan $n/3)"
        repo sync -c -j8 --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune --force-remove-dirty 2>&1 | tee "$slog"
        [ "${PIPESTATUS[0]}" -eq 0 ] && break
        if grep -q 'unsupported checkout state\|not a git repository\|already exists and is not' "$slog"; then
            grep -o '/[^ :]*\.git: unsupported checkout state' "$slog" | sed 's/: unsupported checkout state//' \
                | sort -u | while read -r d; do reset_project "$d"; done
            continue
        fi
        [ "$n" -eq 3 ] && { err "repo sync gagal 3 kali. Coba lagi nanti: bash $SCRIPT sync"; exit 1; }
        sleep 30
    done
    if grep -q 'unsupported checkout state' "$slog" 2>/dev/null; then
        err "Masih ada checkout rusak. Jalankan: bash $SCRIPT reset-ingres  lalu  bash $SCRIPT"
        exit 1
    fi

    # pastikan bagian penting ingres benar-benar lengkap
    if ! [ -f vendor/xiaomi/ingres/ingres-vendor.mk ] || ! [ -f device/xiaomi/ingres-kernel/Image ]; then
        info "Mengulang sync repo ingres yang belum lengkap"
        repo sync -c -j1 --force-sync device/xiaomi/ingres device/xiaomi/ingres-kernel vendor/xiaomi/ingres || true
    fi
    move_leftovers
    patch_source
    ok "Source siap di $SRC"
}

# ----------------------------------------------------------------- build
do_build() {
    cd "$SRC" 2>/dev/null && [ -f build/envsetup.sh ] || { err "Source belum ada. Jalankan: bash $SCRIPT sync"; exit 1; }
    if [ -d out/target/product/ingres ]; then check_disk 20; else check_disk 160; fi

    local jobs ram_gb
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    jobs=${JOBS:-$(( ram_gb / 2 ))}
    [ "$jobs" -gt "$(nproc)" ] && jobs=$(nproc)
    [ "$jobs" -lt 2 ] && jobs=2
    info "Build dengan $jobs job (RAM ${ram_gb} GB, CPU $(nproc) core)"

    move_leftovers
    patch_source
    info "Varian build: $VARIANT"
    set +u   # rom-build.sh / envsetup.sh memakai variabel yang belum diisi
    local start rc
    start=$(date +%s)
    local extra=""
    if [ -f .rom-ingres ] && [ "$(cat .rom-ingres)" != "$ROM" ]; then
        info "ROM berganti ($(cat .rom-ingres) -> $ROM): installclean dulu"
        extra="-i"
    fi
    echo "$ROM" > .rom-ingres
    info "ROM: $ROM_NAME"
    ./rom-build.sh ingres -t "$VARIANT" -j "$jobs" $extra 2>&1 | tee "$LOG"
    rc=${PIPESTATUS[0]}
    echo "Durasi: $(( ($(date +%s) - start) / 60 )) menit"

    if [ "$rc" -ne 0 ] || ! grep -q 'Package Complete' "$LOG"; then
        err "Build gagal. Ini penyebabnya (kirim screenshot bagian ini):"
        echo "------------------------------------------------------------"
        grep -n -m3 -A25 'FAILED:\|error:' "$LOG" || tail -n 60 "$LOG"
        echo "------------------------------------------------------------"
        echo "Setelah source ditambal, lanjutkan dengan: bash $SCRIPT"
        exit 1
    fi

    local p="out/target/product/ingres" zip
    zip=$(ls -t "$p"/*.zip 2>/dev/null | grep -v -e target_files -e '/aospa_ingres-ota' | head -n 1)
    [ -n "$zip" ] || { err "Build selesai tapi zip tidak ditemukan"; exit 1; }
    mkdir -p "$HASIL_DIR"
    cp "$zip" $p/boot.img $p/dtbo.img $p/vendor_boot.img $p/recovery.img "$HASIL_DIR"/ 2>/dev/null
    (cd "$HASIL_DIR" && sha256sum "$(basename "$zip")" > "$(basename "$zip").sha256")
    ok "BUILD BERHASIL"
    ls -lh "$HASIL_DIR"
    if [ "${GOFILE:-1}" != 0 ]; then
        do_upload || echo "Upload GoFile gagal. Ulangi dengan: bash $SCRIPT upload"
    else
        echo "Ambil file di folder $HASIL_DIR lewat SFTP Termius."
    fi
}

# ------------------------------------------------------------- GoFile
gofile_put() {   # $1=file $2=folderId(opsional) $3=token(opsional) -> JSON
    local args=(-sS --retry 3 --retry-delay 10 -F "file=@$1")
    [ -n "$2" ] && args+=(-F "folderId=$2")
    [ -n "$3" ] && args+=(-H "Authorization: Bearer $3")
    curl "${args[@]}" https://upload.gofile.io/uploadfile
}

is_ok() {         # JSON di stdin berstatus ok?
    python3 -c "import json,sys
try: sys.exit(0 if json.load(sys.stdin).get('status')=='ok' else 1)
except Exception: sys.exit(1)"
}

json_get() {     # $1=key -> nilai dari JSON di stdin (data.<key>)
    python3 -c "import json,sys
try: print(json.load(sys.stdin).get('data',{}).get('$1',''))
except Exception: pass"
}

do_upload() {
    local files=() f resp link folder token="${GOFILE_TOKEN:-}" linkfile="$HASIL_DIR/link-gofile.txt"
    for f in "$HASIL_DIR"/*.zip "$HASIL_DIR"/*.sha256 "$HASIL_DIR"/*.img; do
        [ -f "$f" ] && files+=("$f")
    done
    [ ${#files[@]} -gt 0 ] || { err "Tidak ada file di $HASIL_DIR untuk diupload"; return 1; }
    info "Upload ${#files[@]} file ke GoFile (zip ROM paling lama, sabar)"
    folder=""; link=""
    : > "$linkfile"
    for f in "${files[@]}"; do
        info "Upload $(basename "$f") ($(du -h "$f" | cut -f1))"
        resp=$(gofile_put "$f" "$folder" "$token")
        if ! echo "$resp" | is_ok; then
            # coba sekali lagi sebagai file terpisah
            resp=$(gofile_put "$f" "" "${GOFILE_TOKEN:-}")
        fi
        if echo "$resp" | is_ok; then
            [ -n "$folder" ] || folder=$(echo "$resp" | json_get parentFolder)
            [ -n "$token" ] || token=$(echo "$resp" | json_get guestToken)
            local page; page=$(echo "$resp" | json_get downloadPage)
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

# ------------------------------------------------------------------ main
case "$CMD" in
    all)   check_tools; do_sync; do_build ;;
    sync)  check_tools; do_sync ;;
    build) check_tools; do_build ;;
    upload) do_upload ;;
    reset-ingres)
        cd "$SRC" 2>/dev/null || { err "Folder $SRC tidak ada"; exit 1; }
        for d in device/xiaomi/ingres device/xiaomi/ingres-kernel device/xiaomi/sm8450-common \
                 hardware/xiaomi vendor/xiaomi/ingres vendor/xiaomi/sm8450-common; do
            info "Menghapus $d"
            rm -rf "${SRC:?}/$d" "${SRC:?}/.repo/projects/$d.git"
        done
        ok "Selesai. Lanjutkan dengan: bash $SCRIPT"
        ;;
    clean)
        info "Menghapus $SRC/out dan $HASIL_DIR"
        rm -rf "${SRC:?}/out" "$HASIL_DIR"
        ok "Bersih. Ruang disk kosong: $(df -h --output=avail "$HOME" | tail -n 1)"
        ;;
    *) err "Perintah tidak dikenal: $CMD (pakai: all | sync | build | upload | clean | status | bersih | reset-ingres)"; exit 1 ;;
esac
