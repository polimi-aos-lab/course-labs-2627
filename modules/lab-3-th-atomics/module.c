#include <linux/atomic.h>
#include <linux/completion.h>
#include <linux/cpu.h>
#include <linux/err.h>
#include <linux/kthread.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/moduleparam.h>

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Racy versus atomic shared-counter demonstration");

static int variant;
module_param(variant, int, 0444);
MODULE_PARM_DESC(variant, "0=racy read-modify-write, 1=atomic64 operations");

static unsigned long iterations = 1UL << 22;
module_param(iterations, ulong, 0444);
MODULE_PARM_DESC(iterations, "updates executed by each worker");

static long shared_value;
static atomic64_t atomic_value = ATOMIC64_INIT(0);
static DECLARE_COMPLETION(start_gate);
static bool abort_start;

struct counter_worker {
  const char *name;
  long delta;
  struct task_struct *task;
  struct completion done;
};

static struct counter_worker workers[] = {
    {.name = "counter-add", .delta = 1},
    {.name = "counter-sub", .delta = -1},
};

static int counter_thread(void *argument) {
  struct counter_worker *worker = argument;
  unsigned long i;

  wait_for_completion(&start_gate);

  if (READ_ONCE(abort_start))
    return 0;

  if (variant == 0) {
    for (i = 0; i < iterations; i++) {
      long value = READ_ONCE(shared_value);

      cpu_relax();
      WRITE_ONCE(shared_value, value + worker->delta);
    }
  } else {
    for (i = 0; i < iterations; i++)
      atomic64_add(worker->delta, &atomic_value);
  }

  complete(&worker->done);
  return 0;
}

static void stop_workers(unsigned int count) {
  unsigned int i;

  WRITE_ONCE(abort_start, true);
  complete_all(&start_gate);

  for (i = 0; i < count; i++)
    if (!IS_ERR_OR_NULL(workers[i].task))
      kthread_stop(workers[i].task);
}

static int __init counter_demo_init(void) {
  unsigned int cpus = num_online_cpus();
  unsigned int i;
  u64 started_ns;
  u64 elapsed_ns;
  s64 result;

  if (variant < 0 || variant > 1 || !iterations)
    return -EINVAL;

  reinit_completion(&start_gate);
  WRITE_ONCE(abort_start, false);
  shared_value = 0;
  atomic64_set(&atomic_value, 0);

  for (i = 0; i < ARRAY_SIZE(workers); i++) {
    init_completion(&workers[i].done);
    workers[i].task = kthread_create(counter_thread, &workers[i], "%s",
                                     workers[i].name);
    if (IS_ERR(workers[i].task)) {
      int error = PTR_ERR(workers[i].task);

      workers[i].task = NULL;
      stop_workers(i);
      return error;
    }
    kthread_bind(workers[i].task, i % cpus);
  }

  for (i = 0; i < ARRAY_SIZE(workers); i++)
    wake_up_process(workers[i].task);

  started_ns = ktime_get_ns();
  complete_all(&start_gate);

  for (i = 0; i < ARRAY_SIZE(workers); i++)
    wait_for_completion(&workers[i].done);
  elapsed_ns = ktime_get_ns() - started_ns;

  result = variant == 0 ? READ_ONCE(shared_value) : atomic64_read(&atomic_value);
  pr_info("counter_demo variant=%s cpus=%u iterations=%lu result=%lld expected=0 elapsed_ns=%llu\n",
          variant == 0 ? "racy" : "atomic", cpus, iterations, result,
          elapsed_ns);

  return 0;
}

static void __exit counter_demo_exit(void) {
  pr_info("counter_demo unloaded\n");
}

module_init(counter_demo_init);
module_exit(counter_demo_exit);
