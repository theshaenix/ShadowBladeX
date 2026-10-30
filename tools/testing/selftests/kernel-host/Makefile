# SPDX-License-Identifier: GPL-2.0
# These tests compile extracted kernel functions with a native host compiler.
HOSTCC ?= cc
PYTHON ?= python3
TESTS := test_ext4_flush.py test_bore.py test_sbalance.py \
	test_sched_walt_trace.py test_f2fs_checkpoint_stats.py \
	test_devfreq_lifetime.py test_devfreq_limits.py test_adrenoboost.py test_suspend.py test_ksu_profile.py test_ksu_session.py test_ksu_wrapper.py \
	test_ksu_info.py test_ksu_events.py test_ksu_shell.py test_ksu_apk.py test_susfs_private_dir.py \
	test_ksu_force_feature.py test_ksu_umount.py test_susfs_work.py test_ksu_init_rc.py \
	test_process_madvise.py test_process_mrelease.py test_reclaim_advice.py \
	test_dmabuf_sysfs.py \
	test_kprofiles.py test_kprofiles_boost.py test_uclamp.py test_uclamp_group.py test_uclamp_hierarchy.py test_uclamp_percent.py test_uclamp_accounting.py test_uclamp_walt.py \
	test_mglru.py test_mglru_process_reclaim.py test_swap_shadow.py test_binder_alloc.py test_binder_shrinker.py test_binder_spam_owner.py \
	test_zram_recompress.py test_zram_sysfs.py test_zram_lifetime.py test_zram_size_class.py test_zram_publication.py \
	../cpufreq/test_cpu_boost.py

.PHONY: all run_tests
all: run_tests

run_tests:
	@set -e; for test in $(TESTS); do \
		PYTHONDONTWRITEBYTECODE=1 HOSTCC="$(HOSTCC)" $(PYTHON) $$test; \
	done
