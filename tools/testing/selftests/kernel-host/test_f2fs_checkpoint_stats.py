#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Vendor checkpoint counters must not depend on optional F2FS debug stats."""
from test_helpers import ROOT, function_body, run_c

code = r'''
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#define CONFIG_F2FS_BD_STAT 1
#define __user
struct f2fs_bigdata_info {
    unsigned int cp_count, cp_success_count;
    unsigned long long cp_time, max_cp_time, max_cp_submit_time, max_cp_flush_meta_time, max_cp_discard_time;
};
struct f2fs_stat_info { unsigned int cp_count; };
struct f2fs_sb_info {
    struct f2fs_bigdata_info *bd_info;
#ifdef CONFIG_F2FS_STAT_FS
    struct f2fs_stat_info *stat_info;
#endif
};
struct super_block { struct f2fs_sb_info *sbi; };
struct seq_file { void *private; };
struct file { void *private_data; };
#define F2FS_SB(sb) ((sb)->sbi)
#define F2FS_BD_STAT(sbi) ((sbi)->bd_info)
static int locked;
#define bd_lock(sbi) do { assert(!locked); locked++; } while (0)
#define bd_unlock(sbi) do { assert(locked == 1); locked--; } while (0)
#ifdef CONFIG_F2FS_STAT_FS
#define stat_inc_cp_count(si) ((si)->cp_count++)
#else
#define stat_inc_cp_count(si) ((void)0)
#endif
static char output[160];
static void seq_printf(struct seq_file *seq, const char *format, ...) {
    va_list args; va_start(args, format);
    assert(locked == 1);
    vsnprintf(output, sizeof(output), format, args);
    va_end(args);
}
static int copy_from_user(void *dst, const void *src, size_t size) { memcpy(dst, src, size); return 0; }
'''
header = (ROOT / 'fs/f2fs/of2fs_bigdata.h').read_text()
code += header[header.index('#define bd_inc_val('):header.index('#define bd_inc_array_val(')]
checkpoint = function_body('fs/f2fs/checkpoint.c', 'f2fs_write_checkpoint')
counter = checkpoint[checkpoint.index('\tstat_inc_cp_count('):checkpoint.index('\n\tif (cpc->reason & CP_RECOVERY)')]
code += 'static void checkpoint_stop(struct f2fs_sb_info *sbi) {\n' + counter + '\n}\n'
source = 'fs/f2fs/of2fs_sysfs.c'
code += 'static int of2fs_cp_info_show(struct seq_file *seq, void *p)' + function_body(source, 'of2fs_cp_info_show')
code += 'static ssize_t of2fs_cp_info_write(struct file *file, const char *buf, size_t length, loff_t *ppos)'
code += function_body(source, 'of2fs_cp_info_write')
code += r'''
int main(void) {
    struct f2fs_bigdata_info bd = {0};
    struct f2fs_sb_info sbi = {.bd_info=&bd};
#ifdef CONFIG_F2FS_STAT_FS
    struct f2fs_stat_info debug = {.cp_count=99};
    sbi.stat_info = &debug;
#endif
    struct super_block sb = {&sbi};
    struct seq_file seq = {&sb};
    struct file file = {&seq};
    unsigned int count, successes;
    checkpoint_stop(&sbi); checkpoint_stop(&sbi);
    bd.cp_success_count = 1;
    assert(!of2fs_cp_info_show(&seq, NULL) && !locked);
    assert(sscanf(output, "%u %u", &count, &successes) == 2 && count == 2 && successes == 1);
    assert(of2fs_cp_info_write(&file, "1", 1, NULL) == -EINVAL && bd.cp_count == 2);
    assert(of2fs_cp_info_write(&file, "0", 1, NULL) == 1 && !locked);
    assert(!bd.cp_count && !bd.cp_success_count);
    checkpoint_stop(&sbi);
    assert(!of2fs_cp_info_show(&seq, NULL) && !locked);
    assert(sscanf(output, "%u %u", &count, &successes) == 2 && count == 1 && !successes);
    puts("PASS: vendor F2FS checkpoint stats count and reset independently of debug stats");
}
'''
for config in ['', '#define CONFIG_F2FS_STAT_FS 1\n']:
    run_c(config + code)
