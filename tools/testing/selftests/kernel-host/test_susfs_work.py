#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Exercise pending SUSFS work and allocation/task-work cleanup."""
from test_helpers import ROOT, function_body, run_c

code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#define GFP_ATOMIC 0
#define TWA_RESUME 0
#define pr_err(...) ((void)0)
#define container_of(ptr, type, member) ((type *)((char *)(ptr) - offsetof(type, member)))
struct callback_head { void (*func)(struct callback_head *); };
struct cred { int unused; };
static struct cred root_cred, original_cred;
static const struct cred *ksu_cred = &root_cred, *active_cred = &original_cred;
static int current, susfs_extra_works, allocations, schedules, queue_error, allocation_error;
static bool pending;
static struct callback_head *queued;
static void *kzalloc(size_t size, int flags) {
    if (allocation_error) return NULL;
    allocations++;
    return calloc(1, size);
}
static void kfree(void *p) { if (p) { allocations--; free(p); } }
static bool work_pending(int *work) { return pending; }
static void schedule_work(int *work) { schedules++; }
static const struct cred *override_creds(const struct cred *cred) {
    const struct cred *saved = active_cred;
    active_cred = cred;
    return saved;
}
static void revert_creds(const struct cred *cred) { active_cred = cred; }
static int task_work_add(int task, struct callback_head *cb, int flags) {
    if (queue_error) return -1;
    assert(!queued);
    queued = cb;
    return 0;
}
'''
source = 'drivers/kernelsu/hook/setuid_hook.c'
text = (ROOT / source).read_text()
code += text[text.index('struct susfs_handle_setuid_tw {'):text.index('static void susfs_handle_setuid_tw_func')]
code += 'static void susfs_handle_setuid_tw_func(struct callback_head *cb)'
code += function_body(source, 'susfs_handle_setuid_tw_func')
code += 'static void ksu_handle_extra_susfs_work(void)' + function_body(source, 'ksu_handle_extra_susfs_work')
code += r'''
int main(void) {
    pending = true;
    for (int i = 0; i < 100; i++) ksu_handle_extra_susfs_work();
    assert(!allocations && !schedules && !queued);
    pending = false; allocation_error = 1;
    ksu_handle_extra_susfs_work();
    assert(!allocations && schedules == 1 && !queued);
    allocation_error = 0; queue_error = 1;
    ksu_handle_extra_susfs_work();
    assert(!allocations && schedules == 2 && !queued);
    queue_error = 0;
    ksu_handle_extra_susfs_work();
    assert(allocations == 1 && schedules == 3 && queued);
    queued->func(queued); queued = NULL;
    assert(!allocations && active_cred == &original_cred);
    puts("PASS: pending SUSFS work, allocation failures and callbacks release memory");
}
'''
run_c(code)
