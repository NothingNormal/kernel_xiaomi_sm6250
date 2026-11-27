/* SPDX-License-Identifier: GPL-2.0 */
/*
 * SUSFS v2.4.0 - Linux 4.14 (non-GKI) backport helpers.
 *
 * The functions here are the pieces of the SUS_MOUNT/SUS_KSTAT support that
 * upstream expects from the GKI fs/namespace.c hooks. They are kept in one
 * place because fs/namespace.c only hands out "struct mount", which is private
 * to fs/mount.h, and because a non-GKI 4.14 kernel has no vendor hook to place
 * them in.
 */
#ifndef _LINUX_SUSFS_MOUNT_H
#define _LINUX_SUSFS_MOUNT_H

#include <linux/types.h>
#include <linux/stat.h>

struct mount;
struct vfsmount;
struct dentry;
struct kstatfs;

#ifdef CONFIG_KSU_SUSFS

/*
 * Fake mnt_id/mnt_group_id space that is reserved for the mounts the ksu
 * process creates before /sdcard is decrypted. See susfs_def.h.
 */
#define SUSFS_DEFAULT_KSU_MNT_ID 2000000000
#define SUSFS_DEFAULT_KSU_MNT_GROUP_ID 200000
#define SUSFS_DEFAULT_KSU_MNT_MINOR_DEV (1 << 12)

/*
 * Returns the mnt_id of the first mount walking up the mount tree that is not
 * in the reserved ksu range.
 */
int susfs_get_non_sus_mnt_id_from_mnt(struct mount *orig_mnt);

/*
 * Returns a referenced vfsmount/vfsmount root pair describing the same
 * filesystem but with a real (non reserved) mnt_id, so that statfs() on a sus
 * mount can report the values the stock mount would report.
 * The caller owns both the vfsmount and the mnt_root reference.
 */
struct vfsmount *susfs_get_non_sus_vfsmnt_from_vfsmnt(struct vfsmount *vfsmnt);

/*
 * True when the mount is one of the fake, ksu owned mounts, i.e. when the
 * mnt_id is inside of the reserved range.
 */
bool susfs_is_sus_mnt(struct vfsmount *vfsmnt);

#else /* CONFIG_KSU_SUSFS */

static inline int susfs_get_non_sus_mnt_id_from_mnt(struct mount *orig_mnt)
{
	return 0;
}

static inline struct vfsmount *susfs_get_non_sus_vfsmnt_from_vfsmnt(
							struct vfsmount *vfsmnt)
{
	return NULL;
}

static inline bool susfs_is_sus_mnt(struct vfsmount *vfsmnt)
{
	return false;
}

#endif /* CONFIG_KSU_SUSFS */

#endif /* _LINUX_SUSFS_MOUNT_H */
