#!/usr/bin/env bash
# Prepare the pinned legacy KernelSU Next for the miatoll SELinux array backport.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ksu="$root/KernelSU-Next"
patch="$root/patches/ksun/0001-selinux-native-arrays.patch"
test "$(git -C "$ksu" rev-parse HEAD)" = "e5f5ec998de88b9fc43c62cff8f7ae12d3f4800a"
grep -Eq 'struct avtab_node[[:space:]]*\*\*htable;' "$root/security/selinux/ss/avtab.h"
grep -Eq 'struct ebitmap[[:space:]]*\*type_attr_map_array;' "$root/security/selinux/ss/policydb.h"
grep -Eq 'struct type_datum[[:space:]]*\*\*type_val_to_struct;' "$root/security/selinux/ss/policydb.h"
grep -Eq 'char[[:space:]]*\*\*sym_val_to_name\[SYM_NUM\];' "$root/security/selinux/ss/policydb.h"
if git -C "$ksu" apply --reverse --check "$patch" 2>/dev/null; then
    echo "KernelSU Next SELinux compatibility patch already applied"
else
    git -C "$ksu" apply --check "$patch"
    git -C "$ksu" apply "$patch"
fi
