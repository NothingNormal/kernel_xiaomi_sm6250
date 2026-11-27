# SixFaced for Xiaomi miatoll, based on AnyKernel3 by osm0sis.
properties() { '
kernel.string=SixFaced
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=miatoll
device.name2=curtana
device.name3=excalibur
device.name4=gram
device.name5=joyeuse
'; }

BLOCK=boot
IS_SLOT_DEVICE=auto
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=0
. tools/ak3-core.sh

split_boot
flash_boot
