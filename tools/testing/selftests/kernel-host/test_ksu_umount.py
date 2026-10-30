#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Check KernelSU/SUSFS unmount dispatch, profile guards and task-work cleanup."""
from test_helpers import ROOT, function_body, run_c

source = 'drivers/kernelsu/feature/kernel_umount.c'
text = (ROOT / source).read_text()
code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef unsigned int uid_t;
typedef uint32_t u32;
#define GFP_ATOMIC 0
#define TWA_RESUME 0
#define WEBVIEW_ZYGOTE_UID 1053
#define KERNEL_VERSION(a,b,c) (((a)<<16)|((b)<<8)|(c))
#define LINUX_VERSION_CODE KERNEL_VERSION(4,14,357)
#define unlikely(x) (x)
#define likely(x) (x)
#define pr_info(...) ((void)0)
#define pr_warn(...) ((void)0)
#define pr_err(...) ((void)0)
#define pr_debug(...) ((void)0)
#define container_of(ptr, type, member) ((type *)((char *)(ptr) - offsetof(type, member)))
struct callback_head { void (*func)(struct callback_head *); };
struct cred { int unused; };
struct task_struct { int pid; };
static struct task_struct task = {123};
#define current (&task)
static struct cred root_cred, original_cred;
static const struct cred *ksu_cred = &root_cred, *active_cred = &original_cred;
static bool ksu_module_mounted = true, ksu_kernel_umount_enabled = true;
static bool zygote = true, want_umount = true;
static int allocations, allocation_error, queue_error, lock, mount_list_lock, unmounts, custom_unmounts;
static struct callback_head *queued;
struct mount_entry { char *umountable; unsigned int flags; };
static struct mount_entry mounts[] = {{"/system", 2}, {"/vendor", 0}};
#define list_for_each_entry(entry, head, member) \
    for (entry = mounts; entry < mounts + 2; entry++)
static void down_read(int *l) { assert(!lock); lock++; }
static void up_read(int *l) { assert(lock == 1); lock--; }
static void try_umount(const char *path, int flags) {
    if (active_cred == &original_cred) {
        assert(!lock);
        assert((!strcmp(path, "/system/") && flags == 2) ||
               (!strcmp(path, "/product") && flags == 8));
        custom_unmounts++;
        return;
    }
    assert(active_cred == ksu_cred && lock == 1 && unmounts < 2);
    assert(path == mounts[unmounts].umountable && flags == (int)mounts[unmounts].flags);
    unmounts++;
}
static void *kzalloc(size_t n, int f) {
    if (allocation_error) return NULL;
    allocations++;
    return calloc(1, n);
}
static void kfree(void *p) { if (p) { allocations--; free(p); } }
static int task_work_add(struct task_struct *t, struct callback_head *cb, int flags) {
    if (queue_error) return -1;
    assert(!queued && t == current && flags == TWA_RESUME);
    queued = cb;
    return 0;
}
static const struct cred *override_creds(const struct cred *c) {
    const struct cred *saved = active_cred; active_cred = c; return saved;
}
static void revert_creds(const struct cred *c) { active_cred = c; }
static const struct cred *current_cred(void) { return active_cred; }
static bool is_zygote(const struct cred *c) { return zygote; }
static bool is_appuid(uid_t uid) { return uid % 100000 >= 10000 && uid % 100000 < 20000; }
static bool is_isolated_process(uid_t uid) { return uid % 100000 >= 99000; }
static bool ksu_uid_should_umount(uid_t uid) { return want_umount; }
int ksu_handle_umount(uid_t old_uid, uid_t new_uid);
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
struct path { int id; };
static int path_refs;
static bool missing_native;
static int kern_path(const char *name, int flags, struct path *path) {
    if (!strcmp(name, "/system")) {
        if (missing_native) return -1;
        path->id = 1;
    } else if (!strcmp(name, "/system/")) path->id = 1;
    else if (!strcmp(name, "/vendor")) path->id = 2;
    else if (!strcmp(name, "/product")) path->id = 3;
    else return -1;
    path_refs++;
    return 0;
}
static bool path_equal(const struct path *a, const struct path *b) { return a->id == b->id; }
static void path_put(struct path *p) { assert(path_refs > 0); path_refs--; }
'''
code += 'bool ksu_is_umount_path(const char *mnt)' + function_body(source, 'ksu_is_umount_path')
code += '\n#endif\n'
code += text[text.index('struct umount_tw {'):text.index('void __init ksu_kernel_umount_init')]
code += r'''
#ifdef CONFIG_KSU_SUSFS
static bool manager;
static u32 susfs_zygote_sid;
static int susfs_unmounts, extra_work, marked;
static bool susfs_is_sid_equal(const struct cred *c, u32 sid) { return zygote; }
static bool is_uid_manager(uid_t uid) { return manager; }
static bool ksu_is_allow_uid_for_current(uid_t uid) { return false; }
struct uid { uid_t val; };
static struct uid current_uid(void) { return (struct uid){0}; }
static void disable_seccomp(struct task_struct *t) {}
static void ksu_install_manager_fd_tw_func(struct callback_head *cb) { kfree(cb); }
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
struct st_susfs_try_umount_list { struct { char *target_pathname; int mnt_mode; } info; };
static struct st_susfs_try_umount_list custom_mounts[] = {{{"/system/", 2}}, {{"/product", 8}}};
#define SUSFS_LOGI(...) ((void)0)
#define list_for_each_entry_reverse(entry, head, member) \
    for (int i = 2; i-- && (entry = custom_mounts + i, 1); )
'''
code += 'static void susfs_try_umount_impl(uid_t uid, bool skip_ksu)'
code += function_body('fs/susfs.c', 'susfs_try_umount')
code += r'''
static void susfs_try_umount(uid_t uid, bool skip_ksu) {
    susfs_unmounts++;
    assert(skip_ksu == (queued != NULL));
    susfs_try_umount_impl(uid, skip_ksu);
    assert(!path_refs && !lock);
}
#endif
static void ksu_handle_extra_susfs_work(void) { extra_work++; }
static void susfs_set_current_proc_umounted(void) { marked++; }
'''
hook = 'drivers/kernelsu/hook/setuid_hook.c'
for name in ['is_zygote_isolated_service_uid', 'is_zygote_normal_app_uid']:
    code += f'static bool {name}(uid_t uid)' + function_body(hook, name)
code += 'int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid)'
code += function_body(hook, 'ksu_handle_setresuid')
code += r'''
#endif
static void drain(void) {
    assert(queued && allocations == 1 && !unmounts);
    queued->func(queued); queued = NULL;
    assert(unmounts == 2 && !allocations && !lock && active_cred == &original_cred);
    unmounts = 0;
}
int main(void) {
    assert(ksu_handle_umount(0, 10001) == 1); drain();
    zygote = false;
    assert(!ksu_handle_umount(0, 10001) && !queued);
    zygote = true; want_umount = false;
    assert(!ksu_handle_umount(0, 10001) && !queued);
    assert(ksu_handle_umount(0, 99001) == 1); drain();
    want_umount = true;
    assert(!ksu_handle_umount(0, 1000) && !queued);
    ksu_module_mounted = false;
    assert(!ksu_handle_umount(0, 10001) && !queued);
    ksu_module_mounted = true; ksu_kernel_umount_enabled = false;
    assert(!ksu_handle_umount(0, 10001) && !queued);
    ksu_kernel_umount_enabled = true; ksu_cred = NULL;
    assert(!ksu_handle_umount(0, 10001) && !queued);
    ksu_cred = &root_cred; allocation_error = 1;
    assert(!ksu_handle_umount(0, 10001) && !allocations && !queued);
    allocation_error = 0; queue_error = 1;
    assert(!ksu_handle_umount(0, 10001) && !allocations && !queued);
    queue_error = 0;
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
    assert(ksu_is_umount_path("/system/") && !path_refs && !lock);
    assert(!ksu_is_umount_path("/product") && !path_refs && !lock);
    assert(!ksu_is_umount_path("/missing") && !path_refs && !lock);
    missing_native = true;
    assert(!ksu_is_umount_path("/system/") && !path_refs && !lock);
    missing_native = false;
#endif
#ifdef CONFIG_KSU_SUSFS
    assert(!ksu_handle_setresuid(10001, 10001, 10001)); drain();
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
    assert(susfs_unmounts == 1 && custom_unmounts == 1);
#else
    assert(!susfs_unmounts);
#endif
    assert(extra_work == 1 && marked == 1);
    want_umount = false;
    assert(!ksu_handle_setresuid(10001, 10001, 10001) && !queued && extra_work == 1);
    assert(!ksu_handle_setresuid(99001, 99001, 99001)); drain();
    assert(extra_work == 2 && marked == 2);
    want_umount = true; zygote = false;
    assert(!ksu_handle_setresuid(10001, 10001, 10001) && !queued && extra_work == 2);
    zygote = true; manager = true;
    assert(!ksu_handle_setresuid(10001, 10001, 10001) && queued && extra_work == 2);
    queued->func(queued); queued = NULL;
    assert(!allocations && !unmounts);
    manager = false;
    /* Custom SUSFS paths must still run when no KernelSU modules are mounted. */
    ksu_module_mounted = false;
    assert(!ksu_handle_setresuid(10001, 10001, 10001) && !queued && extra_work == 3);
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
    assert(susfs_unmounts == 3 && custom_unmounts == 4);
    /* Failed KernelSU queueing must leave the overlapping SUSFS path active. */
    ksu_module_mounted = true; allocation_error = 1;
    assert(!ksu_handle_setresuid(10001, 10001, 10001) && !queued && !allocations);
    assert(custom_unmounts == 6);
    allocation_error = 0; queue_error = 1;
    assert(!ksu_handle_setresuid(10001, 10001, 10001) && !queued && !allocations);
    assert(custom_unmounts == 8);
#else
    assert(!susfs_unmounts);
#endif
#endif
    puts("PASS: KernelSU unmounts registered paths with SUSFS and preserves profile/zygote guards");
}
'''
for config in ['', '#define CONFIG_KSU_SUSFS 1\n#define CONFIG_KSU_SUSFS_SUS_MOUNT 1\n',
               '#define CONFIG_KSU_SUSFS 1\n#define CONFIG_KSU_SUSFS_SUS_MOUNT 1\n#define CONFIG_KSU_SUSFS_TRY_UMOUNT 1\n']:
    run_c(config + code)
