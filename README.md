# Device_ingres_aospa

Device tree **Paranoid Android (AOSPA) calcite / Android 17** untuk
**POCO F4 GT / Redmi K50 Gaming (ingres)**.

| Bagian | Repo | Branch |
|---|---|---|
| Device // ingres | [kingD2N/Device_ingres_aospa](https://github.com/kingD2N/Device_ingres_aospa) | `main` |
| Kernel (prebuilt) | [kingD2N/android_device_xiaomi_ingres-kernel](https://github.com/kingD2N/android_device_xiaomi_ingres-kernel) | `calcite` |
| Device // common | [kingD2N/android_device_xiaomi_sm8450-common](https://github.com/kingD2N/android_device_xiaomi_sm8450-common) | `calcite` |
| Hardware Xiaomi | [AOSPA/android_hardware_xiaomi](https://github.com/AOSPA/android_hardware_xiaomi) | `calcite` |
| Vendor // ingres | [kingD2N/proprietary_vendor_xiaomi_ingres](https://github.com/kingD2N/proprietary_vendor_xiaomi_ingres) | `calcite` |
| Vendor // common | [ThankYouMario/proprietary_vendor_xiaomi_sm8450-common](https://github.com/ThankYouMario/proprietary_vendor_xiaomi_sm8450-common) | `calcite` |

Semua repo di atas sudah tercantum di `local_manifests/ingres.xml`
(termasuk repo platform taro: display, gps, agm, audio-hal, pal).

## Build (satu perintah)

Di server (Termius), cukup:

```bash
curl -fsSL -o ~/build-aospa.sh https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/build-aospa.sh
bash ~/build-aospa.sh
```

Script otomatis: `repo init` AOSPA calcite → pasang local manifest → `repo sync`
→ `./rom-build.sh ingres`. Build berjalan di sesi byobu `aospa`, jadi aman kalau Termius ditutup.

| Perintah | Fungsi |
|---|---|
| `bash ~/build-aospa.sh` | sync + build |
| `bash ~/build-aospa.sh sync` | hanya sync |
| `bash ~/build-aospa.sh build` | hanya build (lanjut build sebelumnya) |
| `bash ~/build-aospa.sh status` | lihat progres |
| `bash ~/build-aospa.sh upload` | upload ulang hasil ke GoFile |
| `bash ~/build-aospa.sh bersih` | hapus source/hasil ROM lama (LineageOS, ccache) |
| `bash ~/build-aospa.sh clean` | hapus `out/` |

Varian default **user** (rilis). Untuk build debug: `VARIANT=userdebug bash ~/build-aospa.sh`.

Hasil (zip ROM + boot/dtbo/vendor_boot/recovery) disalin ke `~/hasil-aospa` lalu otomatis
di-upload ke GoFile; link download muncul di layar dan tersimpan di `~/hasil-aospa/link-gofile.txt`
(matikan dengan `GOFILE=0`, pakai akun sendiri dengan `GOFILE_TOKEN=<token>`).

> Source AOSPA butuh ±300 GB. Kalau kuota server tidak cukup untuk LineageOS dan AOSPA
> sekaligus, hapus dulu hasil build LineageOS (`bash ~/build-ingres.sh clean`) atau folder `~/los24`.

### Manual

```bash
mkdir -p ~/aospa && cd ~/aospa
repo init -u https://github.com/AOSPA/manifest -b calcite --git-lfs --depth=1
mkdir -p .repo/local_manifests
curl -fsSL -o .repo/local_manifests/ingres.xml \
  https://raw.githubusercontent.com/kingD2N/Device_ingres_aospa/main/local_manifests/ingres.xml
repo sync -c -j8 --force-sync --no-clone-bundle --no-tags
./rom-build.sh ingres -t user
```

Saat `lunch`, pesan `Error: No beans found for the device (ingres)` dari barista itu
normal (ingres bukan device resmi AOSPA, repo-nya diambil dari local manifest) dan tidak menghentikan build.

## Catatan

- Firmware **tidak** ikut di zip ROM (sama seperti build LineageOS). Flash firmware
  HyperOS OS2.0.8.0.ULJCNXM secara manual sebelum flash ROM.
- Kernel memakai prebuilt di `device/xiaomi/ingres-kernel` (GKI 5.10 + modul ingres:
  `leds-aw22xxx`, `xm_gamekey`, dll).
- Blob vendor (`proprietary-files.txt`) = blob ingres LineageOS 24 + stack audio/display
  Xiaomi (AGM/PAL/audio HAL, displayfeature, SDM) seperti device AOSPA lain di sm8450.
- Ekstrak ulang blob: `./extract-files.py --only-target <ota-full.zip>`
  (atau workflow "Ingres Vendor Blobs (AOSPA calcite)" di kingD2N/firmware_Update).
