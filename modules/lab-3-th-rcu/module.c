#include <linux/completion.h>
#include <linux/cpu.h>
#include <linux/delay.h>
#include <linux/err.h>
#include <linux/jiffies.h>
#include <linux/kthread.h>
#include <linux/list.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/rculist.h>
#include <linux/rcupdate.h>
#include <linux/slab.h>
#include <linux/spinlock.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Vittorio Zaccaria");
MODULE_DESCRIPTION("Unsafe, spinlock, and RCU list comparison");

#define MAX_READERS 8

static int variant;
module_param(variant, int, 0444);
MODULE_PARM_DESC(variant, "0=unsafe, 1=spinlock, 2=RCU");

static unsigned int readers = 3;
module_param(readers, uint, 0444);
MODULE_PARM_DESC(readers, "number of reader threads (1-8)");

static unsigned int duration_ms = 3000;
module_param(duration_ms, uint, 0444);
MODULE_PARM_DESC(duration_ms, "measurement duration in milliseconds");

static unsigned int writer_pause_us = 1000;
module_param(writer_pause_us, uint, 0444);
MODULE_PARM_DESC(writer_pause_us, "pause between writer updates");

static unsigned int list_nodes = 64;
module_param(list_nodes, uint, 0444);
MODULE_PARM_DESC(list_nodes, "number of elements in the shared list");

struct benchmark_node {
  u64 value;
  u64 check;
  struct list_head link;
  struct rcu_head rcu;
};

struct reader_context {
  struct task_struct *task;
  struct completion done;
  u64 traversals;
  u64 violations;
} ____cacheline_aligned_in_smp;

struct writer_context {
  struct task_struct *task;
  struct completion done;
  u64 updates;
  u64 allocation_failures;
} ____cacheline_aligned_in_smp;

static LIST_HEAD(shared_list);
static DEFINE_SPINLOCK(list_lock);
static DECLARE_COMPLETION(start_gate);
static bool abort_start;
static struct reader_context *reader_contexts;
static struct writer_context writer_context;
static unsigned long deadline;

static bool node_is_consistent(const struct benchmark_node *node) {
  u64 value = node->value;
  u64 check = node->check;

  return check == ~value;
}

static void inspect_list(struct reader_context *context) {
  struct benchmark_node *node;

  if (variant == 1)
    spin_lock(&list_lock);
  else if (variant == 2)
    rcu_read_lock();

  if (variant == 2) {
    list_for_each_entry_rcu(node, &shared_list, link)
      if (!node_is_consistent(node))
        context->violations++;
  } else {
    list_for_each_entry(node, &shared_list, link)
      if (!node_is_consistent(node))
        context->violations++;
  }

  if (variant == 1)
    spin_unlock(&list_lock);
  else if (variant == 2)
    rcu_read_unlock();
}

static int reader_thread(void *argument) {
  struct reader_context *context = argument;

  wait_for_completion(&start_gate);

  if (abort_start)
    return 0;
  while (time_before(jiffies, deadline)) {
    inspect_list(context);
    context->traversals++;
    cond_resched();
  }

  complete(&context->done);
  return 0;
}

static void update_unsafe(void) {
  struct benchmark_node *node;
  u64 value;

  if (list_empty(&shared_list))
    return;

  node = list_first_entry(&shared_list, struct benchmark_node, link);
  value = node->value + 1;
  node->value = value;
  udelay(1);
  node->check = ~value;
}

static void update_with_spinlock(void) {
  struct benchmark_node *node;
  u64 value;

  spin_lock(&list_lock);
  if (!list_empty(&shared_list)) {
    node = list_first_entry(&shared_list, struct benchmark_node, link);
    value = node->value + 1;
    node->value = value;
    udelay(1);
    node->check = ~value;
  }
  spin_unlock(&list_lock);
}

static bool update_with_rcu(void) {
  struct benchmark_node *old;
  struct benchmark_node *replacement;

  if (list_empty(&shared_list))
    return false;

  replacement = kmalloc(sizeof(*replacement), GFP_KERNEL);
  if (!replacement)
    return false;

  old = list_first_entry(&shared_list, struct benchmark_node, link);
  replacement->value = old->value + 1;
  replacement->check = ~replacement->value;
  udelay(1);
  list_replace_rcu(&old->link, &replacement->link);

  kfree_rcu(old, rcu);
  return true;
}

static int writer_thread(void *argument) {
  struct writer_context *context = argument;

  wait_for_completion(&start_gate);

  if (abort_start)
    return 0;
  while (time_before(jiffies, deadline)) {
    bool updated = true;

    if (variant == 0)
      update_unsafe();
    else if (variant == 1)
      update_with_spinlock();
    else
      updated = update_with_rcu();

    if (updated)
      context->updates++;
    else
      context->allocation_failures++;

    if (writer_pause_us)
      usleep_range(writer_pause_us, writer_pause_us + 50);
    else
      cond_resched();
  }

  complete(&context->done);
  return 0;
}

static void free_current_list(void) {
  struct benchmark_node *node;
  struct benchmark_node *temporary;

  list_for_each_entry_safe(node, temporary, &shared_list, link) {
    list_del(&node->link);
    kfree(node);
  }
}

static int initialize_list(void) {
  unsigned int i;

  for (i = 0; i < list_nodes; i++) {
    struct benchmark_node *node = kmalloc(sizeof(*node), GFP_KERNEL);

    if (!node) {
      free_current_list();
      return -ENOMEM;
    }
    node->value = i;
    node->check = ~node->value;
    INIT_LIST_HEAD(&node->link);
    list_add_tail(&node->link, &shared_list);
  }
  return 0;
}

static void stop_created_tasks(unsigned int reader_count) {
  unsigned int i;

  abort_start = true;
  complete_all(&start_gate);

  for (i = 0; i < reader_count; i++)
    if (!IS_ERR_OR_NULL(reader_contexts[i].task))
      kthread_stop(reader_contexts[i].task);
}

static int create_tasks(void) {
  unsigned int cpus = num_online_cpus();
  unsigned int i;

  for (i = 0; i < readers; i++) {
    struct reader_context *context = &reader_contexts[i];

    init_completion(&context->done);
    context->task = kthread_create(reader_thread, context, "list-reader/%u", i);
    if (IS_ERR(context->task)) {
      int error = PTR_ERR(context->task);

      context->task = NULL;
      stop_created_tasks(i);
      return error;
    }
    kthread_bind(context->task, i % cpus);
  }

  init_completion(&writer_context.done);
  writer_context.task =
      kthread_create(writer_thread, &writer_context, "list-writer");
  if (IS_ERR(writer_context.task)) {
    int error = PTR_ERR(writer_context.task);

    writer_context.task = NULL;
    stop_created_tasks(readers);
    return error;
  }
  kthread_bind(writer_context.task, readers % cpus);
  return 0;
}

static int __init list_demo_init(void) {
  static const char *const names[] = {"unsafe", "spinlock", "rcu"};
  unsigned int i;
  u64 traversals = 0;
  u64 violations = 0;
  int error;

  if (variant < 0 || variant > 2 || readers < 1 || readers > MAX_READERS ||
      !duration_ms || !list_nodes)
    return -EINVAL;

  error = initialize_list();
  if (error)
    return error;

  abort_start = false;
  reader_contexts = kcalloc(readers, sizeof(*reader_contexts), GFP_KERNEL);
  if (!reader_contexts) {
    free_current_list();
    return -ENOMEM;
  }

  reinit_completion(&start_gate);
  memset(&writer_context, 0, sizeof(writer_context));
  error = create_tasks();
  if (error) {
    kfree(reader_contexts);
    reader_contexts = NULL;
    free_current_list();
    return error;
  }

  deadline = jiffies + msecs_to_jiffies(duration_ms);
  for (i = 0; i < readers; i++)
    wake_up_process(reader_contexts[i].task);
  wake_up_process(writer_context.task);
  complete_all(&start_gate);

  for (i = 0; i < readers; i++)
    wait_for_completion(&reader_contexts[i].done);
  wait_for_completion(&writer_context.done);

  for (i = 0; i < readers; i++) {
    traversals += reader_contexts[i].traversals;
    violations += reader_contexts[i].violations;
  }

  pr_info("list_demo variant=%s cpus=%u readers=%u duration_ms=%u writer_pause_us=%u traversals=%llu updates=%llu violations=%llu alloc_failures=%llu\n",
          names[variant], num_online_cpus(), readers, duration_ms,
          writer_pause_us, traversals, writer_context.updates, violations,
          writer_context.allocation_failures);

  if (variant == 2)
    rcu_barrier();
  kfree(reader_contexts);
  reader_contexts = NULL;
  return 0;
}

static void __exit list_demo_exit(void) {
  free_current_list();
  pr_info("list_demo unloaded\n");
}

module_init(list_demo_init);
module_exit(list_demo_exit);
