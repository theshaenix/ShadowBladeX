#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Size-bounded init readers must consume KernelSU's appended boot actions."""
import re
from test_helpers import ROOT, function_body, run_c

source = 'drivers/kernelsu/runtime/ksud_integration.c'
text = (ROOT / source).read_text()
rc = re.search(r'static const char KERNEL_SU_RC\[\] =.*?;', text, re.S).group()
code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#pragma GCC diagnostic ignored "-Wsign-compare"
#define KERNEL_SU_DOMAIN "ksu"
#define KSUD_PATH "/data/adb/ksud"
#define __user
#define pr_info(...) ((void)0)
struct file { bool init_rc; };
struct kstat { long long size; };
static bool ksu_init_rc_hook = true, init_cred = true;
static bool is_init(bool cred) { return cred; }
static bool current_cred(void) { return init_cred; }
static bool is_init_rc(struct file *file) { return file->init_rc; }
static unsigned int loads;
static void load_module_rc_once(void) { loads++; }
static char *module_rc_buf;
static size_t module_rc_len;
static ssize_t module_rc_pos, ksu_rc_pos;
static void free_module_rc(void) { module_rc_buf = NULL; module_rc_len = 0; }
static int copy_to_user(void *to, const void *from, size_t n) {
    memcpy(to, from, n); return 0;
}
static char original[60309];
static ssize_t orig_read(struct file *file, char *buf, size_t count, long long *pos) {
    size_t left = sizeof(original) - *pos;
    if (count > left) count = left;
    memcpy(buf, original + *pos, count);
    *pos += count;
    return count;
}
'''
code += rc + '\nconst size_t ksu_rc_len = sizeof(KERNEL_SU_RC) - 1;\n'
code += 'void ksu_handle_init_rc_stat(struct file *file, struct kstat *stat)'
code += function_body(source, 'ksu_handle_init_rc_stat')
code += 'static ssize_t read_proxy(struct file *file, char *buf, size_t count, long long *pos)'
code += function_body(source, 'read_proxy')
code += r'''
static void read_sized(bool adjust, bool custom_rc) {
    struct file file = { true };
    struct kstat stat = { sizeof(original) };
    const char custom[] = "\non boot\n    setprop test.ksu 1\n";
    char output[sizeof(original) + sizeof(KERNEL_SU_RC) + sizeof(custom)];
    long long pos = 0;
    size_t done = 0;
    ksu_rc_pos = module_rc_pos = 0;
    module_rc_buf = custom_rc ? (char *)custom : NULL;
    module_rc_len = custom_rc ? strlen(custom) : 0;
    if (adjust) ksu_handle_init_rc_stat(&file, &stat);
    while (done < (size_t)stat.size) {
        size_t count = stat.size - done;
        if (count > 128) count = 128;
        ssize_t n = read_proxy(&file, output + done, count, &pos);
        assert(n > 0 && (size_t)n <= count);
        done += n;
    }
    assert(!memcmp(output, original, sizeof(original)));
    if (!adjust) {
        assert(!ksu_rc_pos);
        return;
    }
    assert(ksu_rc_pos == (ssize_t)ksu_rc_len);
    assert(!memcmp(output + sizeof(original), KERNEL_SU_RC, ksu_rc_len));
    assert(strstr(KERNEL_SU_RC, " post-fs-data\n"));
    assert(strstr(KERNEL_SU_RC, " services\n"));
    assert(strstr(KERNEL_SU_RC, " boot-completed\n"));
    if (custom_rc) assert(!memcmp(output + sizeof(original) + ksu_rc_len, custom, strlen(custom)));
}
int main(void) {
    struct file file = { true };
    struct kstat stat = { sizeof(original) };
    memset(original, 'x', sizeof(original));
    read_sized(false, false); /* Reproduces the ROM reader missing all boot actions. */
    read_sized(true, false);
    read_sized(true, true);
    unsigned int before = loads;
    init_cred = false;
    ksu_handle_init_rc_stat(&file, &stat);
    init_cred = true; file.init_rc = false;
    ksu_handle_init_rc_stat(&file, &stat);
    file.init_rc = true; ksu_init_rc_hook = false;
    ksu_handle_init_rc_stat(&file, &stat);
    assert(stat.size == sizeof(original) && loads == before);
    puts("PASS: bounded init reads consume boot and custom actions; other callers keep their file size");
}
'''
run_c(code)
