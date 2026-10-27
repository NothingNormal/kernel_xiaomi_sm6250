#!/usr/bin/env bash
#
# build.sh - reproducible miatoll (SM6250/Atoll, non-GKI 4.14) kernel build
#
# Used by .github/workflows/build.yml and usable locally.
#
# Required environment:
#   CLANG_PATH   directory whose bin/ contains clang, ld.lld, llvm-* and the
#                aarch64-linux-gnu- binutils (e.g. Proton Clang root)
# Optional:
#   ARCH                         default arm64
#   DEFCONFIG                    default vendor/xiaomi/miatoll_defconfig
#   OUT_DIR                      default out
#   JOBS                         default $(nproc)
#   EXTRA_KCFLAGS                extra KBUILD cflags (default: -Wno-error)
#   HOST_CC / HOST_LD / HOST_AR  host toolchain (default gcc/ld/ar)
#
# Why the tool variables are passed on the make command line: this 4.14
# kbuild hard-assigns CC = $(CROSS_COMPILE)gcc and friends in the top
# Makefile, so exported environment variables cannot override them; make
# command-line assignments have the highest precedence.
#
# Why HOSTCC=gcc while the target is fully LLVM: old lld (e.g. Proton Clang
# 13's lld) cannot parse the .relr.dyn sections of modern glibc, so host
# tools are linked with the system GNU toolchain. The kernel image itself is
# built 100% with clang + ld.lld + the LLVM integrated assembler.
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH="${ARCH:-arm64}"
DEFCONFIG="${DEFCONFIG:-vendor/xiaomi/miatoll_defconfig}"
OUT_DIR="${OUT_DIR:-out}"
JOBS="${JOBS:-$(nproc)}"
EXTRA_KCFLAGS="${EXTRA_KCFLAGS:--Wno-error}"
HOST_CC="${HOST_CC:-gcc}"
HOST_LD="${HOST_LD:-ld}"
HOST_AR="${HOST_AR:-ar}"

if [ -z "${CLANG_PATH:-}" ] || [ ! -x "$CLANG_PATH/bin/clang" ]; then
  echo "ERROR: set CLANG_PATH to a toolchain directory containing bin/clang" >&2
  exit 1
fi

export PATH="$CLANG_PATH/bin:$PATH"
export ARCH
export SUBARCH="$ARCH"
export LLVM_IAS=1
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-miatoll-ci}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-kernel-ci}"

# Tool arguments shared by every make invocation.
MAKE_TOOLS=(
  CC=clang
  HOSTCC="$HOST_CC"
  CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE=aarch64-linux-gnu-
  LLVM_IAS=1
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  READELF=llvm-readelf
  STRIP=llvm-strip
  HOSTLD="$HOST_LD"
  HOSTAR="$HOST_AR"
  KCFLAGS="$EXTRA_KCFLAGS"
)

echo "==> clang version"
clang --version | head -2
ld.lld --version | head -1
echo "==> defconfig: $DEFCONFIG"

rm -rf "$OUT_DIR"
make O="$OUT_DIR" ARCH="$ARCH" "$DEFCONFIG"
make O="$OUT_DIR" ARCH="$ARCH" olddefconfig

# Module-free build assertion: this kernel ships everything built-in and the
# AnyKernel3 zip carries no .ko files, so a stray module is a packaging bug.
mod_count=$(grep -c '=m$' "$OUT_DIR/.config" || true)
if [ "$mod_count" -ne 0 ]; then
  echo "ERROR: $mod_count symbols are configured as modules (=m); no modules are shipped:" >&2
  grep '=m$' "$OUT_DIR/.config" >&2
  exit 1
fi

echo "==> building kernel, DTBs and DTBO (-j$JOBS)"
make -j"$JOBS" O="$OUT_DIR" ARCH="$ARCH" "${MAKE_TOOLS[@]}"

echo "==> verifying build products"
test -s "$OUT_DIR/arch/arm64/boot/Image.gz"
test -s "$OUT_DIR/arch/arm64/boot/dtbo.img"
test -s "$OUT_DIR/arch/arm64/boot/dts/qcom/cust-atoll-ab.dtb"
for dev in curtana excalibur gram joyeuse; do
  test -s "$OUT_DIR/arch/arm64/boot/dts/qcom/${dev}-atoll-ab-idp-overlay.dtbo"
done

make -s O="$OUT_DIR" ARCH="$ARCH" "${MAKE_TOOLS[@]}" kernelrelease | tee "$OUT_DIR/kernel.release"

echo "==> build OK:"
ls -la "$OUT_DIR/arch/arm64/boot/Image.gz" \
       "$OUT_DIR/arch/arm64/boot/dtbo.img" \
       "$OUT_DIR/arch/arm64/boot/dts/qcom/cust-atoll-ab.dtb"
