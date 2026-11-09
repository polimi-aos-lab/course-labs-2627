#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/kfifo.h>
#include <linux/module.h>
#include <linux/uaccess.h>

MODULE_LICENSE("GPL");

#define BASE 0x2F8

static int major;
static DEFINE_MUTEX(lock);
static DEFINE_KFIFO(fifo, char, 64);
static DECLARE_WAIT_QUEUE_HEAD(wq);
static unsigned int dropped;

static ssize_t uart_write(struct file *f, const char __user *buf, size_t n,
                          loff_t *off) {
  size_t i;
  char c;

  mutex_lock(&lock);
  for (i = 0; i < n && !get_user(c, buf + i); i++) {
    while (!(inb(BASE + 5) & 0x20))
      cpu_relax();
    outb(c, BASE);
  }
  mutex_unlock(&lock);
  return i || !n ? i : -EFAULT;
}

static irqreturn_t uart_irq(int irq, void *dev) {
  if ((inb(BASE + 2) & 0x0f) != 0x04)
    return IRQ_NONE;
  if (!kfifo_put(&fifo, inb(BASE)))
    dropped++;
  wake_up_interruptible(&wq);
  return IRQ_HANDLED;
}

static ssize_t uart_read(struct file *f, char __user *buf, size_t n,
                         loff_t *off) {
  unsigned int copied;
  int err;

  do {
    if (wait_event_interruptible(wq, !kfifo_is_empty(&fifo)))
      return -ERESTARTSYS;
    mutex_lock(&lock);
    err = kfifo_to_user(&fifo, buf, n, &copied);
    mutex_unlock(&lock);
  } while (!err && !copied && n);
  return err ? err : copied;
}

static const struct file_operations fops = {
    .owner = THIS_MODULE,
    .write = uart_write,
    .read = uart_read,
};

static int __init uart_init(void) {
  if (!request_region(BASE, 8, "serialaos"))
    return -EBUSY;
  if (request_irq(3, uart_irq, 0, "serialaos", &fifo)) {
    release_region(BASE, 8);
    return -EBUSY;
  }
  major = register_chrdev(0, "serialaos", &fops);
  if (major < 0) {
    free_irq(3, &fifo);
    release_region(BASE, 8);
    return major;
  }
  outb(0x08, BASE + 4);
  outb(0x01, BASE + 1);
  pr_info("serialaos: major=%d\n", major);
  return 0;
}

static void __exit uart_exit(void) {
  unregister_chrdev(major, "serialaos");
  outb(0x00, BASE + 1);
  free_irq(3, &fifo);
  release_region(BASE, 8);
  pr_info("serialaos: removed, dropped=%u\n", dropped);
}

module_init(uart_init);
module_exit(uart_exit);
