# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers - miatoll MIUI 14 (Android 12) tuning

### AnyKernel setup
# global properties
properties() { '
kernel.string=Kinesis-Omega kernel for miatoll (MIUI 14 / Android 12 ready)
kernel.compiler=Proton Clang 13 (LLVM/LLD, Polly + ThinLTO)
kernel.made=GitHub Actions CI
kernel.version=4.14.357-openela
message.word=
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=miatoll
device.name2=curtana
device.name3=gram
device.name4=joyeuse
device.name5=excalibur
supported.versions=10 - 17
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel setup
# boot shell variables.
# miatoll (Redmi Note 9 Pro family / POCO M2 Pro) is an A-only device:
# there are no boot slots, so IS_SLOT_DEVICE must stay 0.
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# Back up the current boot and DTBO first when /data is available.
# This ZIP only ever writes the boot partition; the DTBO backup is kept as
# an extra recovery option because a mismatched dtbo is the #1 cause of
# black-screen/bootloop on MIUI for custom kernels.
backup_partition() {
  backup_src=$1;
  backup_dst=$2;
  backup_name=$3;

  if [ ! -b "$backup_src" ]; then
    ui_print "[!] $backup_name partition not found; skipping backup.";
    return 1;
  fi;

  if dd if="$backup_src" of="$backup_dst" bs=4096; then
    ui_print "[+] $backup_name backup saved: $backup_dst";
  else
    rm -f "$backup_dst";
    ui_print "[!] $backup_name backup failed; proceeding anyway.";
    return 1;
  fi;
}

# mountpoint may not exist in every recovery's shell, /proc/mounts always does.
is_mounted() {
  grep -q " $1 " /proc/mounts 2>/dev/null || mountpoint -q "$1" 2>/dev/null;
}

backup_original_partitions() {
  if ! is_mounted /data; then
    ui_print "[!] /data is not mounted; skipping optional boot backups.";
    return;
  fi;

  backup_stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null);
  [ -n "$backup_stamp" ] || backup_stamp=latest;
  backup_dir="/sdcard/miatoll-kernel-backup-$backup_stamp";

  if ! mkdir -p "$backup_dir"; then
    ui_print "[!] Cannot create backup folder on /sdcard; proceeding anyway.";
    return;
  fi;

  ui_print " ";
  ui_print "[+] Backing up current boot and DTBO ...";
  backup_partition "$BLOCK" "$backup_dir/boot.img" "Boot";
  backup_partition /dev/block/bootdevice/by-name/dtbo "$backup_dir/dtbo.img" "DTBO";
}

backup_original_partitions;

## AnyKernel install
# MIUI-safe strategy: unpack the boot image already on the device and replace
# ONLY the kernel (Image.gz). The stock MIUI ramdisk, cmdline, base address,
# DTB and all AVB metadata are inherited untouched, and the dtbo partition is
# never written - this is what lets the kernel boot on MIUI 14 without a
# vendor/DTBO mismatch. A freshly built dtbo.img and DTB ship under extras/
# for advanced users who explicitly want them.
split_boot;
flash_boot;
## end boot install

ui_print " ";
ui_print "[+] Kernel installed. MIUI ramdisk/DTB/dtbo preserved.";
ui_print "[+] Reboot and enjoy.";
