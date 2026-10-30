#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Reject truncated and out-of-bounds APK signing-block lengths."""
from test_helpers import function_body, run_c

code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <limits.h>
#include <stdio.h>
#include <sys/types.h>
typedef uint32_t u32;
typedef uint64_t u64;
struct file { const unsigned char *data; size_t size; };
static ssize_t kernel_read(struct file *f, void *out, size_t size, loff_t *pos) {
    if (*pos < 0 || (size_t)*pos > f->size) return -1;
    size_t available = f->size - (size_t)*pos;
    if (size > available) size = available;
    memcpy(out, f->data + *pos, size);
    *pos += size;
    return size;
}
'''
source = 'drivers/kernelsu/manager/apk_sign.c'
code += 'static bool read_exact(struct file *fp, void *buffer, size_t size, loff_t *pos, loff_t end)'
code += function_body(source, 'read_exact')
code += 'static bool read_length_prefixed_end(struct file *fp, loff_t *pos, loff_t container_end, loff_t *value_end)'
code += function_body(source, 'read_length_prefixed_end')
code += r'''
int main(void) {
    unsigned char data[12] = {0};
    u32 length = 8, value;
    memcpy(data, &length, sizeof(length));
    struct file f = {data, sizeof(data)};
    loff_t pos = 0, end = -1;
    assert(read_length_prefixed_end(&f, &pos, 12, &end) && pos == 4 && end == 12);
    pos = 0;
    assert(!read_length_prefixed_end(&f, &pos, 11, &end));
    length = UINT32_MAX;
    memcpy(data, &length, sizeof(length));
    pos = 0;
    assert(!read_length_prefixed_end(&f, &pos, 12, &end));
    pos = 0; f.size = 3;
    assert(!read_length_prefixed_end(&f, &pos, 12, &end));
    pos = -1;
    assert(!read_exact(&f, &value, sizeof(value), &pos, 12));
    pos = 13;
    assert(!read_exact(&f, &value, sizeof(value), &pos, 12));
    pos = 0;
    assert(!read_exact(&f, &value, sizeof(value), &pos, -1));
    puts("PASS: APK signing-block reads reject truncation and invalid lengths");
}
'''
run_c(code)
