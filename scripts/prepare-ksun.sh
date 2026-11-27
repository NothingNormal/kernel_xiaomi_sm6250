#!/usr/bin/env bash
# Prepare the pinned legacy KernelSU Next for the miatoll kernel:
#   - 0001-selinux-native-arrays.patch: let the legacy SELinux helpers talk to
#     the native (non flex_array) SELinux policy structures of this tree.
#   - 0002-susfs-v2.4.0-ksu-integration.patch: the KernelSU side of SUSFS
#     v2.4.0 (menuconfig entries, command endpoint, lifecycle hooks).
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ksu="$root/KernelSU-Next"

test "$(git -C "$ksu" rev-parse HEAD)" = "e5f5ec998de88b9fc43c62cff8f7ae12d3f4800a"

apply_patch() {
    local patch="$1" name="$2"
    test -f "$patch"
    if git -C "$ksu" apply --reverse --check "$patch" 2>/dev/null; then
        echo "KernelSU Next $name already applied"
    else
        git -C "$ksu" apply --check "$patch"
        git -C "$ksu" apply "$patch"
        echo "KernelSU Next $name applied"
    fi
}

# The native array backport only makes sense on a tree whose SELinux policy
# structures are the native ones, refuse to silently patch anything else.
grep -Eq 'struct avtab_node[[:space:]]*\*\*htable;' "$root/security/selinux/ss/avtab.h"
grep -Eq 'struct ebitmap[[:space:]]*\*type_attr_map_array;' "$root/security/selinux/ss/policydb.h"
grep -Eq 'struct type_datum[[:space:]]*\*\*type_val_to_struct;' "$root/security/selinux/ss/policydb.h"
grep -Eq 'char[[:space:]]*\*\*sym_val_to_name\[SYM_NUM\];' "$root/security/selinux/ss/policydb.h"

apply_patch "$root/patches/ksun/0001-selinux-native-arrays.patch" \
    "SELinux compatibility patch"

# SUSFS keeps its per-task state in the thread flags, which only exist when the
# thread_info lives in the task_struct. Refuse to patch a tree that cannot
# provide them instead of failing later with a compile error.
if grep -qx 'CONFIG_KSU_SUSFS=y' "$root/arch/arm64/configs/vendor/xiaomi/miatoll_defconfig"; then
    grep -Eq '^config THREAD_INFO_IN_TASK$' "$root/init/Kconfig"
    grep -q 'select THREAD_INFO_IN_TASK' "$root/arch/arm64/Kconfig"
    apply_patch "$root/patches/ksun/0002-susfs-v2.4.0-ksu-integration.patch" \
        "SUSFS v2.4.0 integration patch"
fi
