// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2023-2024 Sultan Alsawaf <sultan@kerneltoast.com>.
 */

/**
 * DOC: Capacity Aware Superset Scheduler (CASS) description
 *
 * The Capacity Aware Superset Scheduler (CASS) optimizes runqueue selection of
 * CFS tasks. By using CPU capacity as a basis for comparing the relative
 * utilization between different CPUs, CASS fairly balances load across CPUs of
 * varying capacities. This results in improved multi-core performance,
 * especially when CPUs are overutilized because CASS doesn't clip a CPU's
 * utilization when it eclipses the CPU's capacity.
 *
 * As a superset of capacity aware scheduling, CASS implements a hierarchy of
 * criteria to determine the better CPU to wake a task upon between CPUs that
 * have the same relative utilization. This way, single-core performance,
 * latency, and cache affinity are all optimized where possible.
 *
 * CASS doesn't feature explicit energy awareness but its basic load balancing
 * principle results in decreased overall energy, often better than what is
 * possible with explicit energy awareness. By fairly balancing load based on
 * relative utilization, all CPUs are kept at their lowest P-state necessary to
 * satisfy the overall load at any given moment.
 */

struct cass_cpu_cand {
	int cpu;
	unsigned int exit_lat;
	unsigned long cap;
	unsigned long cap_orig;
	unsigned long raw_util;
	unsigned long util;
};

static __always_inline
unsigned long cass_cpu_util(int cpu, int this_cpu, bool sync)
{
	struct cfs_rq *cfs_rq = &cpu_rq(cpu)->cfs;
	unsigned long util = READ_ONCE(cfs_rq->avg.util_avg);

	/* Deduct @current's util from this CPU if this is a sync wake */
	if (sync && cpu == this_cpu)
		sub_positive(&util, task_util(current));

	if (sched_feat(UTIL_EST))
		util = max_t(unsigned long, util,
			     READ_ONCE(cfs_rq->avg.util_est.enqueued));

	return util;
}

/*
 * The margin used when comparing utilization with CPU capacity.
 *
 * (default: ~20%)
 */
#define fits_capacity(cap, max)	((cap) * 1280 < (max) * 1024)

/* Returns true if @a is a better CPU than @b */
static __always_inline
bool cass_cpu_better(const struct cass_cpu_cand *a,
		     const struct cass_cpu_cand *b,
		     int this_cpu, int prev_cpu, bool sync, bool boosted)
{
#define cass_cmp(a, b) ({ res = (long)(a) - (long)(b); })
#define cass_eq(a, b) ({ res = (a) == (b); })
	long res;

	/* Prefer the CPU that fits the combined CPU + task utilization */
	if (cass_cmp(fits_capacity(a->raw_util, a->cap),
		     fits_capacity(b->raw_util, b->cap)))
		goto done;

	/*
	 * Energy-aware cluster packing for unboosted tasks: when both CPUs fit
	 * the combined load comfortably, keep background/daemon/light tasks on
	 * the efficient Kryo 465 Silver cluster so the Gold Cortex-A76 cluster
	 * stays in deep power collapse. Boosted tasks (top-app UI, SurfaceFlinger,
	 * Circle to Search / Google Lens, games) skip this and get full Gold
	 * Cortex-A76 access immediately.
	 */
	if (!boosted && fits_capacity(a->raw_util, a->cap) &&
	    cass_cmp(b->cap_orig, a->cap_orig))
		goto done;

	/*
	 * Prefer the current CPU for sync wakes, except when a boosted top-app
	 * task is woken from a LITTLE core while a higher-capacity Gold core
	 * candidate is available.
	 */
	if (sync &&
	    (!boosted ||
	     capacity_orig_of(this_cpu) >= max(a->cap_orig, b->cap_orig)) &&
	    (cass_eq(a->cpu, this_cpu) || !cass_cmp(b->cpu, this_cpu)))
		goto done;

	/* Prefer the CPU with lower relative utilization */
	if (cass_cmp(b->util, a->util))
		goto done;

	/* Prefer the CPU with higher capacity */
	if (cass_cmp(a->cap, b->cap))
		goto done;

	/*
	 * Prefer the shallowest idle state (smaller exit_lat) so waking an idle
	 * CPU incurs minimal wakeup latency while leaving deeper-sleeping CPUs
	 * undisturbed in cluster power collapse.
	 */
	if (cass_cmp(b->exit_lat, a->exit_lat))
		goto done;

	/* Prefer the previous CPU */
	if (cass_eq(a->cpu, prev_cpu) || !cass_cmp(b->cpu, prev_cpu))
		goto done;

	/* Prefer the CPU that shares a cache with the previous CPU */
	if (cass_cmp(cpus_share_cache(a->cpu, prev_cpu),
		     cpus_share_cache(b->cpu, prev_cpu)))
		goto done;

	/* @a isn't a better CPU than @b. @res must be <=0 to indicate such. */
done:
	/* @a is a better CPU than @b if @res is positive */
	return res > 0;
}

static int cass_best_cpu(struct task_struct *p, int prev_cpu, bool sync,
			 bool boosted)
{
	/* Initialize @best such that @best always has a valid CPU at the end */
	struct cass_cpu_cand cands[2], *best = cands, *curr;
	int this_cpu = raw_smp_processor_id();
	struct cpuidle_state *idle_state;
	bool has_idle = false;
	unsigned long p_util;
	long margin;
	int cidx = 0, cpu;

	/*
	 * Get the utilization for this task, incorporating schedtune margin so
	 * newly woken/thawed top-app workers (e.g. Google Lens / Circle to
	 * Search / SurfaceFlinger) immediately reflect foreground demand while
	 * negative-boost background tasks stay damped.
	 */
	p_util = task_util_est(p);
	margin = schedtune_task_margin(p);
	if (margin > 0)
		p_util = min_t(unsigned long, SCHED_CAPACITY_SCALE,
			       p_util + (unsigned long)margin);
	else if (margin < 0)
		sub_positive(&p_util, (unsigned long)(-margin));

	/*
	 * Find the best CPU to wake @p on. The RCU read lock is needed for
	 * idle_get_state().
	 */
	rcu_read_lock();
	for_each_cpu_and(cpu, &p->cpus_allowed, cpu_active_mask) {
		/* Use the free candidate slot */
		struct rq *rq = cpu_rq(cpu);
		curr = &cands[cidx];
		curr->cpu = cpu;

		/*
		 * Check if this CPU is idle.
		 * For sync wakes, treat the current CPU as idle if @current is the
		 * only running task.
		 */
		if ((sync && cpu == this_cpu && rq->nr_running == 1) || idle_cpu(cpu)) {
			/* Discard any previous non-idle candidate */
			if (!has_idle)
				best = curr;
			has_idle = true;

			/* Nonzero exit latency indicates this CPU is idle */
			curr->exit_lat = 1;

			/* Add on the actual idle exit latency, if any */
			idle_state = idle_get_state(cpu_rq(cpu));
			if (idle_state)
				curr->exit_lat += idle_state->exit_latency;
		} else {
			/* Skip non-idle CPUs if there's an idle candidate */
			if (has_idle)
				continue;

			/* Zero exit latency indicates this CPU isn't idle */
			curr->exit_lat = 0;
		}

		/* Get this CPU's utilization, possibly without @current */
		curr->raw_util = cass_cpu_util(cpu, this_cpu, sync);

		/*
		 * Add @p's utilization to this CPU if it's not @p's CPU, to
		 * find what this CPU's utilization would look like with @p.
		 */
		if (cpu != task_cpu(p))
			curr->raw_util += p_util;

		/*
		 * Get the current and max capacity of this CPU.
		 */
		curr->cap = max_t(unsigned long, capacity_of(cpu), 1);
		curr->cap_orig = capacity_orig_of(cpu);

		/* Calculate the relative utilization for this CPU candidate */
		curr->util = curr->raw_util * SCHED_CAPACITY_SCALE / curr->cap;

		/*
		 * Check if this CPU is better than the best CPU found so far.
		 * If @best == @curr then there's no need to compare them, but
		 * cidx still needs to be changed to the other candidate slot.
		 */
		if (best == curr ||
		    cass_cpu_better(curr, best, this_cpu, prev_cpu,
				    sync, boosted)) {
			best = curr;
			cidx ^= 1;
		}
	}
	rcu_read_unlock();

	return best->cpu;
}

static int cass_select_task_rq_fair(struct task_struct *p, int prev_cpu,
				    int sd_flag, int wake_flags,
				    int sibling_count_hint)
{
	bool sync;
	bool boosted = schedtune_prefer_idle(p) > 0 ||
		       schedtune_task_boost(p) > 0;

	/*
	 * Don't balance unboosted tasks on exec since their load is unknown,
	 * but allow boosted top-app tasks to spread onto idle big CPUs.
	 */
	if ((sd_flag & SD_BALANCE_EXEC) && !boosted)
		return prev_cpu;

	/*
	 * If there aren't any valid CPUs which are active, then just return the
	 * first valid CPU since it's possible for certain types of tasks to run
	 * on inactive CPUs.
	 */
	if (unlikely(!cpumask_intersects(&p->cpus_allowed, cpu_active_mask)))
		return cpumask_first(&p->cpus_allowed);

	/* cass_best_cpu() needs the task's utilization, so sync it up */
	if (!(sd_flag & SD_BALANCE_FORK))
		sync_entity_load_avg(&p->se);

	sync = (wake_flags & WF_SYNC) && !(current->flags & PF_EXITING);
	return cass_best_cpu(p, prev_cpu, sync, boosted);
}
