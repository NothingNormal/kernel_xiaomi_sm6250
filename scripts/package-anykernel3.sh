#!/usr/bin/env bash
#
# package-anykernel3.sh - turn the built kernel into a recovery-flashable zip
#
# Strategy (MIUI 14 safe): the zip contains Image.gz at its root, so
# AnyKernel3 repacks the boot image already on the phone and replaces only
# the kernel. The stock MIUI ramdisk, DTB, cmdline and AVB metadata stay
# untouched and the dtbo partition is never written. Freshly built DTB /
# DTBO artifacts are placed under extras/ for advanced users only.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${OUT_DIR:-out}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-artifacts}"
AK3_REF="${AK3_REF:-master}"
AK3_URL="${AK3_URL:-https://github.com/osm0sis/AnyKernel3.git}"
STAGE="$(pwd)/.ak3-stage"

BOOT="$OUT_DIR/arch/arm64/boot"
DTS_QCOM="$BOOT/dts/qcom"

for f in "$BOOT/Image.gz" "$BOOT/dtbo.img" "$DTS_QCOM/cust-atoll-ab.dtb"; do
  [ -s "$f" ] || { echo "ERROR: missing build product $f (run scripts/build.sh first)" >&2; exit 1; }
done

KERNEL_RELEASE="$(cat "$OUT_DIR/kernel.release" 2>/dev/null || make -s O="$OUT_DIR" ARCH=arm64 kernelrelease)"
STAMP="$(date +%Y%m%d-%H%M%S)"
ZIP_NAME="miatoll-kernel-${KERNEL_RELEASE}-${STAMP}.zip"

echo "==> fetching AnyKernel3 ($AK3_REF)"
rm -rf "$STAGE"
git clone --depth=1 --branch "$AK3_REF" "$AK3_URL" "$STAGE"
rm -rf "$STAGE/.git" "$STAGE/README.md"

echo "==> installing miatoll anykernel.sh"
cp -f AnyKernel3/anykernel.sh "$STAGE/anykernel.sh"

# Kernel image at the zip root: AK3 swaps this into the existing boot image.
cp -f "$BOOT/Image.gz" "$STAGE/Image.gz"

# Optional, never auto-flashed artifacts.
mkdir -p "$STAGE/extras/dtbo"
cp -f "$DTS_QCOM/cust-atoll-ab.dtb" "$STAGE/extras/cust-atoll-ab.dtb"
cp -f "$BOOT/dtbo.img" "$STAGE/extras/dtbo.img"
for dev in curtana excalibur gram joyeuse; do
  cp -f "$DTS_QCOM/${dev}-atoll-ab-idp-overlay.dtbo" "$STAGE/extras/dtbo/"
done

cat > "$STAGE/extras/README.txt" <<EOF
miatoll kernel - optional artifacts
===================================

These files are NOT flashed by the installer. The installer replaces only the
kernel (Image.gz) inside your current boot image and preserves the stock
ramdisk, DTB, cmdline, AVB flags and the dtbo partition - this is required
for booting MIUI 14 (Android 12).

cust-atoll-ab.dtb    - built-in DTB (cust-atoll-ab base for the whole family)
dtbo.img             - combined DTBO image (curtana/excalibur/gram/joyeuse)
dtbo/                - the four per-device overlay blobs

Only flash these manually if you know exactly why you need to replace the
stock DTB/DTBO (e.g. matching a custom ROM vendor). A wrong dtbo is the most
common cause of black screens and bootloops on MIUI.
EOF

{
  echo "kernel.release=$KERNEL_RELEASE"
  echo "built.at=$STAMP"
  echo "toolchain=$(clang --version 2>/dev/null | head -1 || echo unknown)"
  echo "defconfig=vendor/xiaomi/miatoll_defconfig"
  echo "devices=miatoll,curtana,gram,joyeuse,excalibur"
} > "$STAGE/extras/build-info.txt"

( cd "$STAGE" && sha256sum Image.gz extras/cust-atoll-ab.dtb extras/dtbo.img > extras/SHA256SUMS )

echo "==> creating $ZIP_NAME"
mkdir -p "$ARTIFACTS_DIR"
( cd "$STAGE" && zip -r9 "../$ARTIFACTS_DIR/$ZIP_NAME" . >/dev/null )
cp -f "$STAGE/extras/SHA256SUMS" "$ARTIFACTS_DIR/${ZIP_NAME}.sha256"
rm -rf "$STAGE"

echo "==> package OK"
ls -la "$ARTIFACTS_DIR/$ZIP_NAME"
echo "$ARTIFACTS_DIR/$ZIP_NAME" > "$ARTIFACTS_DIR/latest-zip-path.txt"
