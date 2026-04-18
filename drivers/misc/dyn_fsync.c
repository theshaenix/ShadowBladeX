// SPDX-License-Identifier: GPL-2.0
/*
 * Dynamic fsync control for ShadowBladeX
 *
 * When enabled and the display is on, per-file sync calls from userspace
 * (sync(2) / fsync(2) / fdatasync(2)) are deferred rather than executed
 * immediately, reducing I/O latency during active use.  When the display
 * turns off the pending dirty data is flushed to ensure data integrity.
 *
 * Exposed at /sys/kernel/dyn_fsync/ for FrancoKernel Manager.
 *
 * Based on the dyn_fsync concept by faux123 / franciscofranco.
 */

#define pr_fmt(fmt) "dyn_fsync: " fmt

#include <linux/dyn_fsync.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/msm_drm_notify.h>
#include <linux/notifier.h>
#include <linux/workqueue.h>
#include <linux/writeback.h>

/* Is the feature enabled by the user? */
static bool dyn_fsync_enabled __read_mostly = true;

/* Is the screen currently on? */
static bool screen_on __read_mostly = true;

/*
 * dyn_fsync_active() - test if sync calls should be skipped right now.
 *
 * Returns true when both the driver is enabled AND the screen is on.
 * Called from fs/sync.c.
 */
bool dyn_fsync_active(void)
{
	return dyn_fsync_enabled && screen_on;
}
EXPORT_SYMBOL(dyn_fsync_active);

/* ---------- Flush work on screen-off ---------- */

static void dyn_fsync_flush_work_fn(struct work_struct *work)
{
	/* Walk all mounted superblocks and flush dirty data */
	wakeup_flusher_threads(0, WB_REASON_SYNC);
	pr_debug("flushed dirty data on screen-off\n");
}

static DECLARE_WORK(dyn_fsync_flush_work, dyn_fsync_flush_work_fn);

/* ---------- MSM DRM notifier ---------- */

static int dyn_fsync_drm_notif_cb(struct notifier_block *nb,
				  unsigned long action, void *data)
{
	struct msm_drm_notifier *notif = data;
	int *blank;

	if (action != MSM_DRM_EVENT_BLANK || !notif || !notif->data)
		return NOTIFY_DONE;

	blank = notif->data;

	if (*blank == MSM_DRM_BLANK_UNBLANK) {
		screen_on = true;
	} else if (*blank == MSM_DRM_BLANK_POWERDOWN) {
		screen_on = false;
		/* Flush when going to screen-off to keep data safe */
		if (dyn_fsync_enabled)
			schedule_work(&dyn_fsync_flush_work);
	}

	return NOTIFY_OK;
}

static struct notifier_block dyn_fsync_drm_nb = {
	.notifier_call = dyn_fsync_drm_notif_cb,
};

/* ---------- Sysfs ---------- */

static ssize_t dyn_fsync_active_show(struct kobject *kobj,
				     struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", dyn_fsync_enabled ? 1 : 0);
}

static ssize_t dyn_fsync_active_store(struct kobject *kobj,
				      struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	int val;

	if (kstrtoint(buf, 10, &val))
		return -EINVAL;

	if (val < 0 || val > 1)
		return -EINVAL;

	dyn_fsync_enabled = (val == 1);

	/*
	 * If the feature was just disabled while screen was on, flush now
	 * so no deferred writes are stuck.
	 */
	if (!dyn_fsync_enabled)
		schedule_work(&dyn_fsync_flush_work);

	pr_debug("%s\n", dyn_fsync_enabled ? "enabled" : "disabled");
	return count;
}

static struct kobj_attribute dyn_fsync_active_attr =
	__ATTR(dyn_fsync_active, 0664,
	       dyn_fsync_active_show, dyn_fsync_active_store);

static struct attribute *dyn_fsync_attrs[] = {
	&dyn_fsync_active_attr.attr,
	NULL,
};

static struct attribute_group dyn_fsync_attr_group = {
	.attrs = dyn_fsync_attrs,
};

static struct kobject *dyn_fsync_kobj;

/* ---------- Module init / exit ---------- */

static int __init dyn_fsync_init(void)
{
	int ret;

	dyn_fsync_kobj = kobject_create_and_add("dyn_fsync", kernel_kobj);
	if (!dyn_fsync_kobj)
		return -ENOMEM;

	ret = sysfs_create_group(dyn_fsync_kobj, &dyn_fsync_attr_group);
	if (ret) {
		kobject_put(dyn_fsync_kobj);
		return ret;
	}

	ret = msm_drm_register_client(&dyn_fsync_drm_nb);
	if (ret) {
		sysfs_remove_group(dyn_fsync_kobj, &dyn_fsync_attr_group);
		kobject_put(dyn_fsync_kobj);
		return ret;
	}

	pr_info("Dynamic fsync initialised (enabled=%d)\n", dyn_fsync_enabled);
	return 0;
}

static void __exit dyn_fsync_exit(void)
{
	msm_drm_unregister_client(&dyn_fsync_drm_nb);
	cancel_work_sync(&dyn_fsync_flush_work);
	sysfs_remove_group(dyn_fsync_kobj, &dyn_fsync_attr_group);
	kobject_put(dyn_fsync_kobj);
}

module_init(dyn_fsync_init);
module_exit(dyn_fsync_exit);
MODULE_AUTHOR("ShadowBladeX");
MODULE_DESCRIPTION("Dynamic fsync - skip sync while screen is on");
MODULE_LICENSE("GPL v2");
