/* SPDX-License-Identifier: GPL-2.0 */
/*
 * SELinux services exported to the rest of the kernel.
 */
#ifndef _LINUX_SELINUX_H
#define _LINUX_SELINUX_H

#include <linux/types.h>

#ifdef CONFIG_SECURITY_SELINUX
bool selinux_is_enabled(void);
#else
static inline bool selinux_is_enabled(void)
{
	return false;
}
#endif

#endif /* _LINUX_SELINUX_H */
