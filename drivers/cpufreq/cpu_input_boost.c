// SPDX-License-Identifier: GPL-2.0
/*
 * CPU Input Boost driver for SM7125 (atoll)
 *
 * Boosts CPU frequency on touch/key input events and on display wake-up
 * to reduce latency. Parameters accessible via FrancoKernel Manager at
 * /sys/module/cpu_input_boost/parameters/.
 *
 * Inspired by Sultan Alsawaf's cpu_input_boost and the QCom cpu-boost driver.
 */

#define pr_fmt(fmt) "cpu_input_boost: " fmt

#include <linux/cpu.h>
#include <linux/cpufreq.h>
#include <linux/input.h>
#include <linux/kernel.h>
#include <linux/moduleparam.h>
#include <linux/msm_drm_notify.h>
#include <linux/slab.h>
#include <linux/workqueue.h>

/* Mask bits for cluster classification */
#define CPU_IS_LP(cpu)	(BIT(cpu) & CONFIG_LITTLE_CPU_MASK)
#define CPU_IS_PERF(cpu)	(BIT(cpu) & CONFIG_BIG_CPU_MASK)

enum boost_state {
	BOOST_IDLE,
	INPUT_BOOST,
	WAKE_BOOST,
};

static bool enabled __read_mostly = true;
module_param(enabled, bool, 0644);

static unsigned int input_boost_duration_ms __read_mostly =
	CONFIG_INPUT_BOOST_DURATION_MS;
module_param(input_boost_duration_ms, uint, 0644);

static unsigned int wake_boost_duration_ms __read_mostly =
	CONFIG_WAKE_BOOST_DURATION_MS;
module_param(wake_boost_duration_ms, uint, 0644);

static unsigned int input_boost_freq_lp __read_mostly =
	CONFIG_INPUT_BOOST_FREQ_LP;
module_param(input_boost_freq_lp, uint, 0644);

static unsigned int input_boost_freq_perf __read_mostly =
	CONFIG_INPUT_BOOST_FREQ_PERF;
module_param(input_boost_freq_perf, uint, 0644);

static unsigned int max_boost_freq_lp __read_mostly =
	CONFIG_MAX_BOOST_FREQ_LP;
module_param(max_boost_freq_lp, uint, 0644);

static unsigned int max_boost_freq_perf __read_mostly =
	CONFIG_MAX_BOOST_FREQ_PERF;
module_param(max_boost_freq_perf, uint, 0644);

static unsigned int min_freq_lp __read_mostly = CONFIG_MIN_FREQ_LP;
module_param(min_freq_lp, uint, 0644);

static unsigned int min_freq_perf __read_mostly = CONFIG_MIN_FREQ_PERF;
module_param(min_freq_perf, uint, 0644);

/* Per-CPU current boost minimum frequency */
static DEFINE_PER_CPU(unsigned int, boost_min);

/* Current boost state */
static atomic_t boost_state = ATOMIC_INIT(BOOST_IDLE);

static struct workqueue_struct *boost_wq;
static struct delayed_work boost_remove_work;
static struct notifier_block cpu_notif;
static struct notifier_block msm_drm_notif;

static void set_boost_min_for_cluster(unsigned int freq_lp,
				      unsigned int freq_perf)
{
	unsigned int cpu;

	get_online_cpus();
	for_each_online_cpu(cpu) {
		if (CPU_IS_LP(cpu))
			per_cpu(boost_min, cpu) = freq_lp;
		else if (CPU_IS_PERF(cpu))
			per_cpu(boost_min, cpu) = freq_perf;
	}
	put_online_cpus();
}

static void apply_boost_policies(void)
{
	unsigned int cpu;

	get_online_cpus();
	for_each_online_cpu(cpu)
		cpufreq_update_policy(cpu);
	put_online_cpus();
}

static void clear_boost(struct work_struct *work)
{
	unsigned int cpu;

	/* Clear per-CPU boost mins */
	get_online_cpus();
	for_each_online_cpu(cpu) {
		if (CPU_IS_LP(cpu))
			per_cpu(boost_min, cpu) = min_freq_lp;
		else if (CPU_IS_PERF(cpu))
			per_cpu(boost_min, cpu) = min_freq_perf;
	}
	put_online_cpus();

	atomic_set(&boost_state, BOOST_IDLE);
	apply_boost_policies();
}

static void do_input_boost(void)
{
	if (!enabled)
		return;

	/* Input boost takes lower priority than an ongoing wake boost */
	if (atomic_read(&boost_state) == WAKE_BOOST)
		return;

	cancel_delayed_work_sync(&boost_remove_work);
	atomic_set(&boost_state, INPUT_BOOST);

	set_boost_min_for_cluster(input_boost_freq_lp, input_boost_freq_perf);
	apply_boost_policies();

	queue_delayed_work(boost_wq, &boost_remove_work,
			   msecs_to_jiffies(input_boost_duration_ms));
}

static void do_wake_boost(void)
{
	if (!enabled)
		return;

	cancel_delayed_work_sync(&boost_remove_work);
	atomic_set(&boost_state, WAKE_BOOST);

	set_boost_min_for_cluster(max_boost_freq_lp, max_boost_freq_perf);
	apply_boost_policies();

	queue_delayed_work(boost_wq, &boost_remove_work,
			   msecs_to_jiffies(wake_boost_duration_ms));
}

/* ---------- CPUFREQ ADJUST notifier ---------- */

static int cpu_notif_cb(struct notifier_block *nb, unsigned long action,
			void *data)
{
	struct cpufreq_policy *policy = data;
	unsigned int cpu = policy->cpu;
	unsigned int bmin;

	if (action != CPUFREQ_ADJUST)
		return NOTIFY_DONE;

	bmin = per_cpu(boost_min, cpu);
	if (!bmin)
		return NOTIFY_DONE;

	cpufreq_verify_within_limits(policy, bmin, UINT_MAX);
	return NOTIFY_OK;
}

/* ---------- Input handler ---------- */

static void cpu_boost_input_event(struct input_handle *handle,
				  unsigned int type, unsigned int code,
				  int value)
{
	do_input_boost();
}

static int cpu_boost_input_connect(struct input_handler *handler,
				   struct input_dev *dev,
				   const struct input_device_id *id)
{
	struct input_handle *handle;
	int ret;

	handle = kzalloc(sizeof(*handle), GFP_KERNEL);
	if (!handle)
		return -ENOMEM;

	handle->dev = dev;
	handle->handler = handler;
	handle->name = "cpu_input_boost";

	ret = input_register_handle(handle);
	if (ret)
		goto free_handle;

	ret = input_open_device(handle);
	if (ret)
		goto unregister_handle;

	return 0;

unregister_handle:
	input_unregister_handle(handle);
free_handle:
	kfree(handle);
	return ret;
}

static void cpu_boost_input_disconnect(struct input_handle *handle)
{
	input_close_device(handle);
	input_unregister_handle(handle);
	kfree(handle);
}

static const struct input_device_id cpu_boost_ids[] = {
	/* Touch screen */
	{
		.flags = INPUT_DEVICE_ID_MATCH_EVBIT |
			 INPUT_DEVICE_ID_MATCH_ABSBIT,
		.evbit = { BIT_MASK(EV_ABS) },
		.absbit = { [BIT_WORD(ABS_MT_POSITION_X)] =
				BIT_MASK(ABS_MT_POSITION_X) },
	},
	/* Keyboard / power key */
	{
		.flags = INPUT_DEVICE_ID_MATCH_EVBIT,
		.evbit = { BIT_MASK(EV_KEY) },
	},
	{ },
};

static struct input_handler cpu_boost_input_handler = {
	.event		= cpu_boost_input_event,
	.connect	= cpu_boost_input_connect,
	.disconnect	= cpu_boost_input_disconnect,
	.name		= "cpu_input_boost",
	.id_table	= cpu_boost_ids,
};

/* ---------- MSM DRM (display) notifier ---------- */

static int msm_drm_notif_cb(struct notifier_block *nb, unsigned long action,
			    void *data)
{
	struct msm_drm_notifier *notif = data;
	int *blank;

	if (action != MSM_DRM_EVENT_BLANK || !notif || !notif->data)
		return NOTIFY_DONE;

	blank = notif->data;

	if (*blank == MSM_DRM_BLANK_UNBLANK)
		do_wake_boost();

	return NOTIFY_OK;
}

/* ---------- Module init / exit ---------- */

static int __init cpu_input_boost_init(void)
{
	int ret;
	unsigned int cpu;

	/* Initialise per-CPU min to configured static minimums */
	get_online_cpus();
	for_each_online_cpu(cpu) {
		if (CPU_IS_LP(cpu))
			per_cpu(boost_min, cpu) = min_freq_lp;
		else if (CPU_IS_PERF(cpu))
			per_cpu(boost_min, cpu) = min_freq_perf;
	}
	put_online_cpus();

	boost_wq = alloc_workqueue("cpu_input_boost_wq",
				   WQ_HIGHPRI | WQ_UNBOUND, 1);
	if (!boost_wq) {
		pr_err("Failed to allocate workqueue\n");
		return -ENOMEM;
	}

	INIT_DELAYED_WORK(&boost_remove_work, clear_boost);

	cpu_notif.notifier_call = cpu_notif_cb;
	ret = cpufreq_register_notifier(&cpu_notif, CPUFREQ_POLICY_NOTIFIER);
	if (ret) {
		pr_err("Failed to register cpufreq notifier: %d\n", ret);
		goto destroy_wq;
	}

	ret = input_register_handler(&cpu_boost_input_handler);
	if (ret) {
		pr_err("Failed to register input handler: %d\n", ret);
		goto unregister_cpufreq;
	}

	msm_drm_notif.notifier_call = msm_drm_notif_cb;
	ret = msm_drm_register_client(&msm_drm_notif);
	if (ret) {
		pr_err("Failed to register msm_drm notifier: %d\n", ret);
		goto unregister_input;
	}

	pr_info("Initialised (input_boost_freq lp=%u perf=%u, wake_boost lp=%u perf=%u)\n",
		input_boost_freq_lp, input_boost_freq_perf,
		max_boost_freq_lp, max_boost_freq_perf);
	return 0;

unregister_input:
	input_unregister_handler(&cpu_boost_input_handler);
unregister_cpufreq:
	cpufreq_unregister_notifier(&cpu_notif, CPUFREQ_POLICY_NOTIFIER);
destroy_wq:
	destroy_workqueue(boost_wq);
	return ret;
}

static void __exit cpu_input_boost_exit(void)
{
	msm_drm_unregister_client(&msm_drm_notif);
	input_unregister_handler(&cpu_boost_input_handler);
	cpufreq_unregister_notifier(&cpu_notif, CPUFREQ_POLICY_NOTIFIER);
	cancel_delayed_work_sync(&boost_remove_work);
	destroy_workqueue(boost_wq);
}

module_init(cpu_input_boost_init);
module_exit(cpu_input_boost_exit);
MODULE_AUTHOR("ShadowBladeX");
MODULE_DESCRIPTION("CPU input/wake boost for SM7125");
MODULE_LICENSE("GPL v2");
