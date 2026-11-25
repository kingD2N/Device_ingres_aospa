#!/usr/bin/env bash
# Simpan token GitHub (baca-saja) di akun server ini supaya git/repo sync tidak ditolak 403.
#
# Pakai:
#   bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/github-token.sh)
#   bash <(curl -fsSL .../github-token.sh) hapus     # hapus token dari akun ini
#
# Token hanya disimpan di ~/.git-credentials (izin 600, hanya akun ini). Env var server
# dan ~/.gitconfig lain tidak diubah selain menambah credential.helper store bila belum ada.
set -u

# [cd-home] Mulai selalu dari folder home: folder terminal saat ini bisa saja sudah
# dihapus (mis. ~/evox setelah bersih), dan git/repo gagal "Unable to read current
# working directory" kalau dijalankan dari folder yang sudah tidak ada.
cd "$HOME" 2>/dev/null || cd /

info() { echo -e "\033[1;34m[..]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
err()  { echo -e "\033[1;31m[GAGAL]\033[0m $*" >&2; }

command -v git >/dev/null || { err "git tidak ada"; exit 1; }
USER_GH="${GH_USER:-kingD2N}"
CRED="$HOME/.git-credentials"

if [ "${1:-}" = "hapus" ]; then
    printf 'protocol=https\nhost=github.com\nusername=%s\n\n' "$USER_GH" | git credential reject
    ok "Token GitHub dihapus dari akun ini"
    exit 0
fi

# pastikan git memakai penyimpanan kredensial
if ! git config --global --get-all credential.helper | grep -qx 'store'; then
    git config --global --add credential.helper store
    info "credential.helper store ditambahkan"
fi

echo "Buat token di GitHub: Settings > Developer settings > Personal access tokens."
echo "Pilih Fine-grained token, akses 'Public repositories (read-only)', tanpa izin lain."
echo "Untuk build kernel juga (menu kernel): pilih 'Only select repositories' > Kernel_NoMount_ingres,"
echo "izin Contents = Read-only. Token itu tetap bisa membaca semua repo publik."
echo "Tempel token di bawah (tidak tampil di layar), lalu Enter."
printf 'Token: '
IFS= read -rs TOKEN
echo
TOKEN="${TOKEN//[[:space:]]/}"
[ -n "$TOKEN" ] || { err "Token kosong"; exit 1; }

# hapus entri lama untuk github.com lalu simpan yang baru
printf 'protocol=https\nhost=github.com\nusername=%s\n\n' "$USER_GH" | git credential reject
printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' "$USER_GH" "$TOKEN" | git credential approve
unset TOKEN
[ -f "$CRED" ] && chmod 600 "$CRED"

info "Tes akses GitHub..."
if GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/Lunaris-AOSP/art.git HEAD 2>/dev/null | grep -q HEAD; then
    ok "Token bekerja. Sekarang jalankan sync lagi dari menu (perintah 4)."
    if GIT_TERMINAL_PROMPT=0 git ls-remote https://github.com/kingD2N/Kernel_NoMount_ingres HEAD 2>/dev/null | grep -q HEAD; then
        ok "Token juga bisa membaca workflow kernel (menu kernel siap dipakai)."
    else
        info "Token ini belum bisa membaca Kernel_NoMount_ingres (hanya perlu untuk menu kernel)."
    fi
else
    err "Tes gagal (token salah/kedaluwarsa, atau IP server masih diblokir GitHub)."
    echo "Cek token lalu coba lagi. Hapus dengan: bash <(curl -fsSL https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/termius/github-token.sh) hapus"
    exit 1
fi
