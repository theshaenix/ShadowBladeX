/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_SELINUX_H
#define _LINUX_SELINUX_H

#ifdef CONFIG_SECURITY_SELINUX
extern int selinux_enabled;
static inline int selinux_is_enabled(void)
{
	return selinux_enabled;
}
#else
static inline int selinux_is_enabled(void)
{
	return 0;
}
#endif

#endif /* _LINUX_SELINUX_H */
