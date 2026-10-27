# MIUI 14 (Android 12) compatibility — miatoll non-GKI kernel

Device family: **miatoll** = Redmi Note 9 Pro/Pro Max (`curtana`),
Redmi Note 9S (`joyeuse`), POCO M2 Pro (`gram`), Redmi Note 9 Pro Max
(`excalibur`). SoC: Qualcomm SM6250/Atoll. This is a **non-GKI** kernel
(Linux 4.14, OpenELA/ELTS 4.14.357 base) — there is no GKI/KMI split, all
drivers are built into the kernel image and the DTB/DTBO still live in the
`boot`/`dtbo` partitions.

## Why custom kernels historically fail to boot MIUI 14 on miatoll

Research against the shipped MIUI kernel config (`arch/arm64/configs/stock_defconfig`,
Linux 4.14.209 Xiaomi config) and community bootloop reports identified three
concrete causes, all addressed here:

1. **Missing memory cgroup (memcg).** MIUI's `lmkd` / ActivityManager memory
   accounting and per-app memory limits use the memory cgroup plus swap
   accounting. Kernels built without it misbehave under memory pressure.
2. **Missing `msm_performance` driver.** MIUI `perfd` (miuiboost /
   powerkeeper) issues CPU fmin/fmax requests through
   `/sys/module/msm_performance`. Without the driver the sysfs writes fail
   and MIUI performance/thermal policy breaks.
3. **DTB/DTBO mismatch.** Replacing the `dtbo` partition (or the DTB inside
   the boot image) with one that does not exactly match the MIUI vendor stack
   breaks panel/touch probing and black-screens the device. The AnyKernel3
   package therefore flashes **only `Image.gz`** and keeps the stock MIUI
   ramdisk, DTB, cmdline, AVB flags and `dtbo` partition byte-for-byte.

## Configuration changes (`arch/arm64/configs/vendor/xiaomi/miatoll_defconfig`)

| Symbol | Value | Reason |
|---|---|---|
| `CONFIG_MEMCG` / `MEMCG_SWAP` / `MEMCG_SWAP_ENABLED` | y | MIUI lmkd + memory cgroup, stock parity |
| `CONFIG_CGROUP_WRITEBACK` | y | memcg dependency, stock parity |
| `CONFIG_MSM_PERFORMANCE` | y | MIUI perfd fmin/fmax sysfs interface |
| `CONFIG_AUDIT` | y | SELinux/auditd parity with stock MIUI (`AUDITSYSCALL` stays off, as on stock) |
| `CONFIG_NETLABEL` | y | Labeled networking (SELinux), stock parity |
| `CONFIG_UTS_NS` | y | Namespace parity with stock MIUI (`PID_NS` stays off, matching stock) |
| `CONFIG_TCP_CONG_BIC` / `TCP_CONG_HTCP` | off | They default to `=m`; no modules are shipped, so the build is kept 100% module-free |

Already present and required for Android 12 (verified, not just assumed):
`EROFS_FS` (+ `EROFS_FS_ZIP` LZ4, selected automatically) for the compressed
read-only system partition, `F2FS_FS` with encryption/verity, `FS_VERITY`,
`OVERLAY_FS`, `INCREMENTAL_FS`, `ANDROID_BINDERFS`, full `BPF_SYSCALL`/JIT,
`SECCOMP`, `ASHMEM`, `ION`, `DM_VERITY`/`DM_CRYPT`, inline crypto (UFS/ICE),
and the miatoll-specific drivers: FTS SPI + Novatek NT36xxx SPI touchpanels,
Goodix GF3208 + FPC1020 fingerprint, qcacld-3.0 Wi-Fi, Spectra camera, KGSL,
QSEECOM, WCD937x/TAS2562 audio and the SMB5/SMB1390/SMB1398 chargers.

## Build-system compatibility fix

The kbuild hardcodes three Polly pass names that were renamed in LLVM 13
(`-polly-loopfusion-greedy`, `-polly-reschedule`, `-polly-postopts`). The
top-level `Makefile` now guards them with `cc-option`, keeping the original
flags on period toolchains (LLVM ≤ 12) and selecting the new names
(`-polly-opt-fusion`, `-polly-opt-simplify-deps`) automatically on Clang
13/14 and newer. The same 4.14 kbuild hard-assigns `CC = $(CROSS_COMPILE)gcc`,
so all LLVM tool variables are passed as **make command-line arguments**
(see `scripts/build.sh`); exporting them is not enough.

## Toolchain

Proton Clang 13 (kdrag0n/proton-clang): self-contained Clang + LLD +
Polly + LLVM tools plus aarch64/arm GNU binutils. The kernel target is built
fully with LLVM (`LLVM_IAS=1`, `LD=ld.lld`); host tools are built with the
runner's GNU gcc/ld because old LLD cannot parse modern glibc `.relr.dyn`.

## Flashing model

* AnyKernel3, device allowlist `miatoll/curtana/gram/joyeuse/excalibur`,
  Android versions 10–17.
* A-only device: `IS_SLOT_DEVICE=0`, block `bootdevice/by-name/boot`.
* `split_boot` + `flash_boot` only — ramdisk/DTB inherited from the phone,
  `dtbo` never written. A backup of the current `boot` and `dtbo` is saved to
  `/sdcard/miatoll-kernel-backup-*` when `/data` is mounted.
* Freshly built `cust-atoll-ab.dtb` and `dtbo.img` are shipped under `extras/`
  but are never flashed automatically.

## CI

`.github/workflows/build.yml` runs on pushes to `arena/**` and manual
dispatch: it regenerates the config, asserts every MIUI/Android-12 symbol
above and the zero-module property, builds `Image.gz` + DTB + `dtbo.img`,
packages the AnyKernel3 ZIP and uploads it as a workflow artifact
(retention 90 days).
