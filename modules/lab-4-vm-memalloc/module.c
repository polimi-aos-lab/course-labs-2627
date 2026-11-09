#include <asm/io.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/proc_fs.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/vmalloc.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Vittorio Zaccaria");
MODULE_DESCRIPTION("Kernel allocation and user-copy demonstration");

#define PAGES 4

struct sample {
  u64 value;
};

static unsigned int constructed;
static struct proc_dir_entry *entry;

static void construct(void *object) {
  ((struct sample *)object)->value = 0;
  constructed++;
}

static int show_pages(void) {
  char *k = kmalloc(PAGES * PAGE_SIZE, GFP_KERNEL);
  char *v;
  int i;

  if (!k)
    return -ENOMEM;
  v = vmalloc(PAGES * PAGE_SIZE);
  if (!v) {
    kfree(k);
    return -ENOMEM;
  }
  for (i = 0; i < PAGES; i++) {
    char *ka = k + i * PAGE_SIZE, *va = v + i * PAGE_SIZE;

    pr_info("kmalloc[%d] va=%px pfn=%lx\n", i, ka,
            (unsigned long)(virt_to_phys(ka) >> PAGE_SHIFT));
    pr_info("vmalloc[%d] va=%px pfn=%lx\n", i, va,
            page_to_pfn(vmalloc_to_page(va)));
  }
  vfree(v);
  kfree(k);
  return 0;
}

static ssize_t receive(struct file *file, const char __user *user,
                       size_t count, loff_t *offset) {
  char text[16];
  unsigned long uncopied;

  if (count > sizeof(text))
    return -E2BIG;
  if (!count)
    return 0;
  uncopied = copy_from_user(text, user, count);
  pr_info("from_user requested=%zu uncopied=%lu\n", count, uncopied);
  if (uncopied)
    return -EFAULT;
  pr_info("received=%.*s\n", (int)count, text);
  return count;
}

static ssize_t send(struct file *file, char __user *user,
                    size_t count, loff_t *offset) {
  static const char reply[] = "kernel!\n";
  size_t length;
  unsigned long uncopied;

  if (*offset < 0)
    return -EINVAL;
  if (*offset >= sizeof(reply) - 1)
    return 0;
  length = min_t(size_t, count, sizeof(reply) - 1 - *offset);
  uncopied = copy_to_user(user, reply + *offset, length);
  pr_info("to_user requested=%zu uncopied=%lu\n", length, uncopied);
  if (uncopied)
    return -EFAULT;
  *offset += length;
  return length;
}

static const struct proc_ops ops = {
    .proc_read = send,
    .proc_write = receive,
};

static int __init lab4_init(void) {
  struct kmem_cache *cache;
  struct sample *object;
  int error = show_pages();

  if (error)
    return error;
  cache = kmem_cache_create("lab4_objects", sizeof(*object), 0, 0, construct);
  if (!cache)
    return -ENOMEM;
  object = kmem_cache_alloc(cache, GFP_KERNEL);
  if (!object) {
    kmem_cache_destroy(cache);
    return -ENOMEM;
  }
  pr_info("cache allocated=1 constructed=%u\n", constructed);
  kmem_cache_free(cache, object);
  kmem_cache_destroy(cache);

  entry = proc_create("lab4", 0600, NULL, &ops);
  if (!entry)
    return -ENOMEM;
  pr_info("/proc/lab4 ready\n");
  return 0;
}

static void __exit lab4_exit(void) {
  proc_remove(entry);
  pr_info("/proc/lab4 removed\n");
}

module_init(lab4_init);
module_exit(lab4_exit);
