#!/bin/sh
# Usage: scripts/package-sixfaced.sh out/arch/arm64/boot/Image SixFaced.zip
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 <arm64 Image> <output.zip>" >&2; exit 2; }
[ -s "$1" ] || { echo "Missing kernel Image: $1" >&2; exit 1; }
magic=$(od -An -tx1 -j56 -N4 "$1" | tr -d ' \n')
[ "$magic" = 41524d64 ] || { echo "Expected an uncompressed arm64 kernel Image" >&2; exit 1; }
root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
upstream="$root/AnyKernel3"
pin=$(git -C "$root" rev-parse HEAD:AnyKernel3)
git -C "$upstream" cat-file -e "$pin:tools/magiskboot" 2>/dev/null || {
    echo "Run git submodule update --init AnyKernel3 first" >&2; exit 1;
}
output=$(realpath -m "$2")
stage=$(mktemp -d)
archive=$(mktemp -d "$(dirname "$output")/.sixfaced.XXXXXX") || { rmdir "$stage"; exit 1; }
trap 'rm -rf "$stage" "$archive"' EXIT
git -C "$upstream" archive -o "$stage/upstream.tar" "$pin" META-INF tools LICENSE
tar -xf "$stage/upstream.tar" -C "$stage"
cp "$root/packaging/miatoll/anykernel.sh" "$stage/anykernel.sh"
cp "$1" "$stage/Image"
(cd "$stage" && zip -q -r "$archive/kernel.zip" META-INF tools LICENSE anykernel.sh Image)
mv "$archive/kernel.zip" "$output"
