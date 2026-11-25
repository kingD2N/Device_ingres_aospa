#!/usr/bin/env bash
# Alat server untuk build ROM ingres (POCO F4 GT): kunci tanda tangan dan ruang disk.
#
# Pakai (atau lewat menu ROM: pilih k / d):
#   bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/server-tools.sh) kunci
#   bash <(curl -fsSL .../server-tools.sh) backup              # backup kunci ke ~/ingres-keys-backup-<tanggal>.tgz
#   bash <(curl -fsSL .../server-tools.sh) pulihkan [file.tgz] # pulihkan kunci dari backup
#   bash <(curl -fsSL .../server-tools.sh) cekttd evox         # cek tanda tangan zip ROM terbaru
#   bash <(curl -fsSL .../server-tools.sh) disk                # ruang disk, folder source & hasil ROM
#
# Kunci tanda tangan kingD2N dipakai SEMUA ROM (sama dengan LineageOS 24). Kunci tidak pernah
# dikirim ke mana pun: backup hanya ditulis di home server, ambil sendiri lewat SFTP.
set -u

# [cd-home] Mulai selalu dari folder home: folder terminal saat ini bisa saja sudah
# dihapus (mis. ~/evox setelah bersih), dan git/repo gagal "Unable to read current
# working directory" kalau dijalankan dari folder yang sudah tidak ada.
cd "$HOME" 2>/dev/null || cd /

KEYS_DIR="${KEYS_DIR:-$HOME/.ingres-keys}"
c_ok=$'\e[1;32m'; c_in=$'\e[1;34m'; c_wr=$'\e[1;33m'; c_er=$'\e[1;31m'; c_dm=$'\e[2m'; c_0=$'\e[0m'
ok()   { echo "${c_ok}[OK]${c_0} $*"; }
info() { echo "${c_in}[..]${c_0} $*"; }
warn() { echo "${c_wr}[!!]${c_0} $*"; }
die()  { echo "${c_er}[GAGAL]${c_0} $*" >&2; exit 1; }

# folder source|folder hasil|nama ROM
ROM_DIRS=(
    "evox|hasil-evox|Evolution X"
    "los24|hasil-los24|LineageOS 24"
    "pixelos|hasil-pixelos|PixelOS"
    "lunaris|hasil-lunaris|Lunaris"
    "alpha|hasil-alpha|AlphaDroid"
    "axion|hasil-axion|AxionOS"
    "ascp|hasil-ascp|ASCP"
    "infinity|hasil-infinity|Infinity X"
    "uwu|hasil-uwu|uwuAOSP"
    "aospa|hasil-aospa|AOSPA / PenguinOS"
    "aospa|hasil-penguin|PenguinOS (hasil)"
    "crdroid|hasil-crdroid|crDroid"
    "rros|hasil-rros|ResurrectedRemix OS"
    "derpfest|hasil-derpfest|DerpFest"
    "clover|hasil-clover|The Clover Project"
)

key_count() { find "$KEYS_DIR" -maxdepth 1 -name '*.pk8' 2>/dev/null | wc -l; }

# Sidik jari (SHA-256, 16 karakter pertama) sebuah sertifikat
fp() { openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//; s/://g' | cut -c1-16; }

backups() { ls -1t "$HOME"/ingres-keys-backup*.tgz "$HOME"/*keys*.tgz 2>/dev/null | awk '!s[$0]++'; }

key_status() {
    local n
    n=$(key_count)
    echo "${c_in}== Kunci tanda tangan kingD2N ==${c_0}"
    echo "   Folder : $KEYS_DIR"
    if [ "$n" -eq 0 ]; then
        warn "Belum ada kunci. Pulihkan dari backup dulu (pilih 2), kalau tidak build berikutnya"
        echo "        membuat kunci BARU yang berbeda (ROM lama harus wipe data)."
    else
        ok "$n kunci ada (LineageOS 12, +1 verifiedboot setelah AxionOS)"
        if [ -f "$KEYS_DIR/releasekey.x509.pem" ]; then
            echo "   Pemilik : $(openssl x509 -in "$KEYS_DIR/releasekey.x509.pem" -noout -subject 2>/dev/null | sed 's/^subject= *//')"
            echo "   Sidik jari releasekey : $(fp "$KEYS_DIR/releasekey.x509.pem")"
            echo "   Sidik jari platform   : $(fp "$KEYS_DIR/platform.x509.pem")"
        fi
    fi
    local b
    b=$(backups)
    if [ -n "$b" ]; then
        echo "   Backup di server:"
        while read -r f; do
            printf '     %s  %s  %s\n' "$(date -r "$f" '+%Y-%m-%d %H:%M')" "$(du -h "$f" | cut -f1)" "$f"
        done <<<"$b"
    else
        warn "Belum ada file backup di home server."
    fi
}

do_backup() {
    [ "$(key_count)" -gt 0 ] || die "Tidak ada kunci di $KEYS_DIR untuk dibackup"
    local f="$HOME/ingres-keys-backup-$(date +%Y%m%d-%H%M).tgz"
    (umask 077; tar czf "$f" -C "$(dirname "$KEYS_DIR")" "$(basename "$KEYS_DIR")") || die "Backup gagal"
    chmod 600 "$f"
    ok "Backup dibuat: $f"
    echo "   Ambil lewat SFTP Termius lalu simpan di HP/cloud pribadi. Jangan dibagikan ke siapa pun."
}

do_restore() {
    local f="${1:-}" tmp src stamp
    if [ -z "$f" ]; then
        f=$(backups | head -n 1)
        [ -n "$f" ] || die "Tidak ada backup di home server. Upload dulu file .tgz lewat SFTP ke folder home."
        read -rp "Pulihkan dari $f ? [Y/n] " a
        case "$a" in n|N) echo "Batal."; return 0 ;; esac
    fi
    [ -f "$f" ] || die "File tidak ada: $f"
    tmp=$(mktemp -d "$HOME/.keys-restore.XXXXXX") || die "Gagal membuat folder sementara"
    chmod 700 "$tmp"
    tar xzf "$f" -C "$tmp" 2>/dev/null || { rm -rf "$tmp"; die "File bukan backup .tgz yang valid: $f"; }
    # backup bisa dibuat dari folder mana saja: cari folder yang berisi releasekey.pk8
    src=$(find "$tmp" -name releasekey.pk8 -printf '%h\n' 2>/dev/null | head -n 1)
    if [ -z "$src" ] || [ ! -s "$src/releasekey.x509.pem" ]; then
        rm -rf "$tmp"; die "Di dalam $f tidak ada releasekey.pk8 / releasekey.x509.pem"
    fi
    if [ "$(key_count)" -gt 0 ]; then
        if [ "$(fp "$KEYS_DIR/releasekey.x509.pem")" = "$(fp "$src/releasekey.x509.pem")" ]; then
            ok "Kunci di server sudah sama dengan backup ini, tidak ada yang diubah."
            rm -rf "$tmp"; return 0
        fi
        warn "Kunci di server BERBEDA dengan backup ini."
        read -rp "Ganti kunci server dengan backup? Ketik YA: " a
        [ "$a" = YA ] || { rm -rf "$tmp"; echo "Batal."; return 0; }
        stamp=$(date +%Y%m%d-%H%M%S)
        mv "$KEYS_DIR" "$KEYS_DIR.lama-$stamp" || { rm -rf "$tmp"; die "Gagal memindah kunci lama"; }
        info "Kunci lama disimpan di $KEYS_DIR.lama-$stamp"
    fi
    mkdir -p "$(dirname "$KEYS_DIR")"
    mv "$src" "$KEYS_DIR" || { rm -rf "$tmp"; die "Gagal memasang kunci"; }
    rm -rf "$tmp"
    chmod 700 "$KEYS_DIR"; chmod 600 "$KEYS_DIR"/* 2>/dev/null
    ok "Kunci dipulihkan: $(key_count) kunci, sidik jari releasekey $(fp "$KEYS_DIR/releasekey.x509.pem")"
}

# Cek tanda tangan zip ROM hasil build: cocokkan otacert dengan releasekey di ~/.ingres-keys
# $1 = nama ROM (evox, crdroid, ...) -> zip terbaru di ~/hasil-<rom>; kosong = semua hasil-*
check_sign() {
    local rom="${1:-}" z zips=() c a b subj d
    b=$(openssl x509 -in "$KEYS_DIR/releasekey.x509.pem" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
    [ -n "$b" ] || warn "Kunci $KEYS_DIR belum ada, hanya menampilkan pemilik sertifikat"
    if [ -n "$rom" ]; then
        d="$HOME/hasil-${rom#hasil-}"
        [ -d "$d" ] || die "Folder $d tidak ada"
        z=$(ls -t "$d"/*.zip 2>/dev/null | head -n 1)
        [ -n "$z" ] && zips+=("$z")
    else
        for d in "$HOME"/hasil-*/; do
            z=$(ls -t "$d"*.zip 2>/dev/null | head -n 1)
            [ -n "$z" ] && zips+=("$z")
        done
    fi
    [ ${#zips[@]} -gt 0 ] || die "Belum ada zip ROM${rom:+ di ~/hasil-${rom#hasil-}}"
    for z in "${zips[@]}"; do
        echo "${c_in}== $(basename "$z")${c_0}"
        c=$(unzip -p "$z" META-INF/com/android/otacert 2>/dev/null)
        if [ -z "$c" ]; then warn "Tidak ada META-INF/com/android/otacert (bukan zip ROM?)"; continue; fi
        subj=$(echo "$c" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject= *//')
        a=$(echo "$c" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
        echo "   Pemilik : $subj"
        if [ -n "$b" ] && [ "$a" = "$b" ]; then ok "Ditandatangani kunci kingD2N ($KEYS_DIR)"
        elif echo "$subj" | grep -q 'android@android.com\|CN *= *Android'; then warn "Kunci uji bawaan (test-keys), BUKAN kunci kingD2N"
        else warn "BUKAN kunci $KEYS_DIR"; fi
    done
}

keys_menu() {
    key_status
    echo
    echo "  1) Backup kunci sekarang"
    echo "  2) Pulihkan kunci dari backup"
    echo "  3) Cek tanda tangan zip ROM hasil build"
    echo "  0) Keluar"
    read -rp "Nomor [0]: " n
    case "${n:-0}" in
        1) do_backup ;;
        2) read -rp "File backup (kosongkan = backup terbaru di home): " f; do_restore "$f" ;;
        3) read -rp "ROM (mis. evox, crdroid; kosongkan = semua): " f; check_sign "$f" ;;
        *) ;;
    esac
}

disk_info() {
    echo "${c_in}== Ruang disk server ==${c_0}"
    df -h "$HOME" | sed 's/^/   /'
    echo "   ${c_dm}Build baru butuh sekitar 160 GB kosong, build lanjutan sekitar 20 GB.${c_0}"
    echo
    echo "${c_in}== Folder ROM di home ==${c_0}"
    local r s h name any=0 ls lh
    for r in "${ROM_DIRS[@]}"; do
        IFS='|' read -r s h name <<<"$r"
        ls=""; lh=""
        [ -d "$HOME/$s" ] && ls="source ~/$s"
        [ -d "$HOME/$h" ] && lh="hasil ~/$h ($(du -sh "$HOME/$h" 2>/dev/null | cut -f1), $(find "$HOME/$h" -maxdepth 1 -name '*.zip' | wc -l) zip)"
        [ -z "$ls$lh" ] && continue
        any=1
        printf '   %-20s %s%s%s\n' "$name" "$ls" "${ls:+${lh:+  |  }}" "$lh"
    done
    [ "$any" = 1 ] || echo "   (belum ada source / hasil ROM)"
    echo "   ${c_dm}Satu akun hanya boleh 1 source ROM. Hapus source ROM lain lewat menu ROM > perintah 'bersih'.${c_0}"
    echo
    if [ "$(key_count)" -gt 0 ]; then ok "Kunci tanda tangan: $(key_count) kunci di $KEYS_DIR"
    else warn "Kunci tanda tangan belum ada di $KEYS_DIR (menu k untuk memulihkan)"; fi
}

case "${1:-kunci}" in
    kunci|keys|k) keys_menu ;;
    status)       key_status ;;
    backup)       do_backup ;;
    pulihkan|restore) do_restore "${2:-}" ;;
    disk|d)       disk_info ;;
    cekttd|cek-ttd|cek) check_sign "${2:-}" ;;
    *) die "Perintah tidak dikenal: $1 (pilihan: kunci, status, backup, pulihkan, disk)" ;;
esac
