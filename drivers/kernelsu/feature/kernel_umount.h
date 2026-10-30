#ifndef __KSU_H_KERNEL_UMOUNT
#define __KSU_H_KERNEL_UMOUNT

#include <linux/types.h>
#include <linux/list.h>
#include <linux/rwsem.h>

void ksu_kernel_umount_init(void);
void ksu_kernel_umount_exit(void);

// Returns 1 when KernelSU unmount work was queued, otherwise 0.
int ksu_handle_umount(uid_t old_uid, uid_t new_uid);
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
bool ksu_is_umount_path(const char *mnt);
#endif

// for the umount list
struct mount_entry {
    char *umountable;
    unsigned int flags;
    struct list_head list;
};
extern struct list_head mount_list;
extern struct rw_semaphore mount_list_lock;

#endif
