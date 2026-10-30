#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Check the v3.4.2 shell-root ancestry restriction."""
from test_helpers import function_body, run_c

code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#define MAX_ANCESTOR_DEPTH 128
#define rcu_read_lock() ((void)0)
#define rcu_read_unlock() ((void)0)
#define rcu_dereference(p) (p)
struct cred { bool adbd, ksu; };
struct task_struct {
    int pid;
    struct cred cred;
    struct task_struct *real_parent;
};
static struct task_struct *current;
static bool ksu_shell_su_adb_only;
static const struct cred *__task_cred(struct task_struct *t) { return &t->cred; }
static bool is_adbd(const struct cred *c) { return c->adbd; }
static bool is_task_ksu_domain(const struct cred *c) { return c->ksu; }
static bool static_branch_unlikely(const bool *enabled) { return *enabled; }
'''
source = 'drivers/kernelsu/feature/shell_su_adb_only.c'
code += 'static bool has_trusted_ancestor(void)' + function_body(source, 'has_trusted_ancestor')
code += 'bool ksu_shell_su_allowed_for_current(void)' + function_body(source, 'ksu_shell_su_allowed_for_current')
code += r'''
int main(void) {
    struct task_struct init = { .pid = 1 };
    struct task_struct parent = { .pid = 2, .real_parent = &init };
    struct task_struct shell = { .pid = 3, .real_parent = &parent };
    current = &shell;
    assert(ksu_shell_su_allowed_for_current());
    ksu_shell_su_adb_only = true;
    assert(!ksu_shell_su_allowed_for_current());
    parent.cred.adbd = true;
    assert(ksu_shell_su_allowed_for_current());
    parent.cred.adbd = false;
    parent.cred.ksu = true;
    assert(ksu_shell_su_allowed_for_current());
    parent.cred.ksu = false;
    init.cred.ksu = true;
    assert(!ksu_shell_su_allowed_for_current());
    /* A malformed ancestor chain must remain bounded and deny root. */
    parent.real_parent = &parent;
    assert(!ksu_shell_su_allowed_for_current());
    puts("PASS: shell root requires an adbd/KernelSU ancestor when restricted");
}
'''
run_c(code)
