#ifndef __KSU_H_KSUD
#define __KSU_H_KSUD

#include <linux/compat.h>
#include <linux/version.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 14, 0)
#include <linux/compiler_types.h>
#else
#include <linux/compiler.h>
#endif
#include <linux/types.h>

#define KSUD_PATH "/data/adb/ksud"

struct filename;

#include "runtime/user_arg_ptr.h"

int ksu_handle_execveat_ksud(int *fd, struct filename **filename_ptr,
			     struct user_arg_ptr *argv,
			     struct user_arg_ptr *envp, int *flags);

void ksu_ksud_init();
void ksu_ksud_exit();

void ksu_stop_input_hook_runtime(void);

extern bool ksu_execveat_hook __read_mostly;

#endif