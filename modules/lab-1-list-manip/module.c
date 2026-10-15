#include "linux/prandom.h" // prandom
#include <linux/module.h>
#include <linux/sched/task.h> // hrtimer
#include <linux/slab.h>       // kmalloc

#define TIME_1SEC_NS 1000000000L

// Define a linked list node structure
struct list_node {
  int data;
  struct list_node *next;
};

struct list_node *head;
struct hrtimer my_timer;

// Helper function to add a node to the list
int add_node(int data, gfp_t flags) {
  struct list_node *new_node = kmalloc(sizeof(*new_node), flags);
  if (!new_node)
    return -ENOMEM;
  new_node->data = data;
  new_node->next = head;
  head = new_node;
  return 0;
}

// Timer handler function
enum hrtimer_restart my_timer_handler(struct hrtimer *timer) {
  struct list_node *cur = head;
  unsigned int rnd;

  pr_info("timer handler invoked \n");

  // Simulate getting data from a device..
  rnd = prandom_u32();

  if (add_node(rnd, GFP_ATOMIC))
    goto rearm;
  // Traverse nodes and remove last element
  while (cur) {
    if (!cur->next->next) {
      kfree(cur->next); // Free cur node
      cur->next = NULL;
    } else {
      cur = cur->next;
    }
  }

  // Restart the timer for periodic execution
rearm:
  hrtimer_forward_now(timer, ns_to_ktime(TIME_1SEC_NS));
  return HRTIMER_RESTART;
}

static void free_nodes(void) {
  while (head) {
    struct list_node *node = head;
    head = head->next;
    kfree(node);
  }
}

// Module initialization function
static int __init my_module_init(void) {
  // Initialize linked list
  int i;
  for (i = 0; i < 3; i++) {
    if (add_node(i, GFP_KERNEL)) {
      free_nodes();
      return -ENOMEM;
    }
  }

  // Initialize and start the timer
  hrtimer_init(&my_timer, CLOCK_MONOTONIC, HRTIMER_MODE_REL);
  my_timer.function = &my_timer_handler;
  pr_info("setting up timer to start in 3 seconds. Now is a good time check "
          "/sys/module/../sections and run gdb "
          "GDB!");
  hrtimer_start(&my_timer, ns_to_ktime(3 * TIME_1SEC_NS), HRTIMER_MODE_REL);

  return 0;
}

// Module cleanup function
static void __exit my_module_exit(void) {
  // Wait for any running callback before freeing its list.
  hrtimer_cancel(&my_timer);
  free_nodes();
}

module_init(my_module_init);
module_exit(my_module_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Subtle Memory Corruption Timer Example");
