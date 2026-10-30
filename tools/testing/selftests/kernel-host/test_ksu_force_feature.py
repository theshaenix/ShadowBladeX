#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Bound forced-feature parsing to its input, including malformed final entries."""
from test_helpers import function_body, run_c

code = r'''
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
typedef uint32_t u32;
typedef uint64_t u64;
#define KSU_FEATURE_MAX 8
#define pr_err(...) ((void)0)
#define pr_info(...) ((void)0)
struct kernel_param { int unused; };
static const char *feature_names[KSU_FEATURE_MAX] = { [0]="su_compat", [3]="adb_root" };
static u64 forced_values[KSU_FEATURE_MAX];
static unsigned long forced_mask[1], forced_pending[1];
#define set_bit(id, mask) (*(mask) |= 1UL << (id))
static int kstrtou64(const char *s, int base, u64 *out) {
    char *end;
    errno = 0;
    *out = strtoull(s, &end, base);
    return errno || s == end || *end || *s == '-' ? -EINVAL : 0;
}
static int kstrtou32(const char *s, int base, u32 *out) {
    u64 value;
    int err = kstrtou64(s, base, &value);
    if (err || value > UINT32_MAX) return -EINVAL;
    *out = value;
    return 0;
}
'''
source = 'drivers/kernelsu/policy/feature.c'
code += 'static int parse_feature_id(const char *name, u32 *id)' + function_body(source, 'parse_feature_id')
code += 'static int force_feature_param_set(const char *val, const struct kernel_param *kp)'
code += function_body(source, 'force_feature_param_set')
code += r'''
int main(void) {
    /* Exact-size arrays let ASan catch advancing past the final terminator. */
    char single[] = "su_compat:1";
    char multiple[] = "su_compat:0,adb_root:1,3:2";
    char malformed[] = ",missing,:1,adb_root:,8:1,su_compat:garbage";
    char trailing[] = "su_compat:1,,";
    assert(!force_feature_param_set(NULL, NULL));
    assert(!force_feature_param_set("", NULL));
    assert(!force_feature_param_set(single, NULL));
    assert(forced_values[0] == 1 && forced_mask[0] == 1 && forced_pending[0] == 1);
    assert(!force_feature_param_set(multiple, NULL));
    assert(!forced_values[0] && forced_values[3] == 2);
    assert(forced_mask[0] == 9 && forced_pending[0] == 9);
    assert(!force_feature_param_set(malformed, NULL));
    assert(!forced_values[0] && forced_values[3] == 2 && forced_mask[0] == 9);
    assert(!force_feature_param_set(trailing, NULL) && forced_values[0] == 1);
    puts("PASS: forced features stop at the terminator and reject malformed entries");
}
'''
run_c(code)
