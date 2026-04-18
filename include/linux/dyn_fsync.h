/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_DYN_FSYNC_H
#define _LINUX_DYN_FSYNC_H

#include <linux/types.h>

#ifdef CONFIG_DYN_FSYNC
bool dyn_fsync_active(void);
#else
static inline bool dyn_fsync_active(void) { return false; }
#endif

#endif /* _LINUX_DYN_FSYNC_H */
