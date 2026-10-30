#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""WALT trace assignments must work with and without fair group scheduling."""
from test_helpers import ROOT, function_body, run_c

source = 'include/trace/events/sched.h'
text = (ROOT / source).read_text()
code = r'''
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint64_t u64;
typedef uint32_t u32;
#define TASK_COMM_LEN 16
#define SCHED_CAPACITY_SHIFT 10
#define container_of(p, type, member) ((type *)((char *)(p) - offsetof(type, member)))
#define do_div(n, d) ((n) /= (d))
struct rq;
struct avg { unsigned long load_avg, util_avg; };
struct cfs_rq {
    unsigned long runnable_load_avg;
    struct avg avg;
#ifdef CONFIG_FAIR_GROUP_SCHED
    struct rq *rq;
#endif
};
struct sched_entity {
    struct avg avg;
#ifdef CONFIG_FAIR_GROUP_SCHED
    struct cfs_rq *my_q;
#endif
};
struct rq { struct cfs_rq cfs; int cpu; u64 prev_runnable_sum; };
struct task_struct { struct sched_entity se; char comm[16]; int pid, cpu; struct { u32 demand; } ravg; };
static struct rq runqueues[2];
static struct rq *cpu_rq(int cpu) { assert(cpu >= 0 && cpu < 2); return &runqueues[cpu]; }
static int cpu_of(struct rq *rq) { return rq->cpu; }
static int task_cpu(struct task_struct *p) { return p->cpu; }
static int __trace_sched_path(struct cfs_rq *rq, char *path, int len) { strcpy(path, "test"); return 5; }
struct entry {
    int cpu, pid;
    char path[32], comm[16];
    unsigned long load, util, util_pelt, util_walt;
};
static struct entry record;
#define __entry (&record)
#define __get_dynamic_array(name) (record.name)
#define __get_dynamic_array_len(name) (sizeof(record.name))
#ifdef CONFIG_SCHED_WALT
static unsigned int sched_ravg_window = 1024, walt_disabled;
static unsigned int sysctl_sched_use_walt_cpu_util = 1, sysctl_sched_use_walt_task_util = 1;
'''
code += text[text.index('#define walt_util('):text.index('\n#endif', text.index('#define walt_util('))]
code += '\n#endif\n'
code += 'static int __trace_sched_cpu(struct cfs_rq *cfs_rq, struct sched_entity *se)'
code += function_body(source, '__trace_sched_cpu')
code += 'static struct cfs_rq *__trace_sched_group_cfs_rq(struct sched_entity *se)'
code += function_body(source, '__trace_sched_group_cfs_rq')
for name, signature in [('sched_load_cfs_rq', 'struct cfs_rq *cfs_rq'), ('sched_load_se', 'struct sched_entity *se')]:
    assignment = text.split('TRACE_EVENT(' + name + ',', 1)[1].split('\n\tTP_fast_assign(', 1)[1].split('\n\t),', 1)[0]
    code += f'static void {name}({signature}) {{\n' + assignment + '\n}\n'
code += r'''
int main(void) {
    struct task_struct task = {.comm="worker", .pid=12, .cpu=1, .ravg.demand=256};
    task.se.avg = (struct avg){44, 33};
    for (int cpu = 0; cpu < 2; cpu++) {
        runqueues[cpu].cpu = cpu;
        runqueues[cpu].prev_runnable_sum = 512;
        runqueues[cpu].cfs.avg = task.se.avg;
        runqueues[cpu].cfs.runnable_load_avg = 55;
#ifdef CONFIG_FAIR_GROUP_SCHED
        runqueues[cpu].cfs.rq = &runqueues[cpu];
#endif
    }
    sched_load_cfs_rq(&runqueues[1].cfs);
    assert(record.cpu == 1 && record.load == 55 && record.util_pelt == 33);
#ifdef CONFIG_SCHED_WALT
    assert(record.util == 512 && record.util_walt == 512);
    walt_disabled = 1;
    sched_load_cfs_rq(&runqueues[1].cfs);
    assert(record.util == 33);
    walt_disabled = 0;
#else
    assert(record.util == 33 && !record.util_walt);
#endif
    sched_load_se(&task.se);
    assert(record.cpu == 1 && record.pid == 12 && !strcmp(record.comm, "worker"));
#ifdef CONFIG_SCHED_WALT
    assert(record.util == 256 && record.util_walt == 256);
    sysctl_sched_use_walt_task_util = 0;
    sched_load_se(&task.se);
    assert(record.util == 33);
#else
    assert(record.util == 33 && !record.util_walt);
#endif
#ifdef CONFIG_FAIR_GROUP_SCHED
    struct cfs_rq child = {.rq=&runqueues[1], .avg={44, 33}};
    struct sched_entity group = {.my_q=&child, .avg={44, 33}};
    sched_load_cfs_rq(&child);
    assert(record.cpu == 1 && record.util == 33 && !record.util_walt);
    sched_load_se(&group);
    assert(record.pid == -1 && record.util == 33 && !record.util_walt);
#endif
    puts("PASS: scheduler traces preserve WALT/PELT values with group scheduling on or off");
}
'''
for config in ['#define CONFIG_SCHED_WALT 1\n',
               '#define CONFIG_SCHED_WALT 1\n#define CONFIG_FAIR_GROUP_SCHED 1\n', '']:
    run_c(config + code)
