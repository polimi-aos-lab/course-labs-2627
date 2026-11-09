#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void) {
  long page = sysconf(_SC_PAGESIZE);
  char *memory;
  int fd;
  ssize_t written, read_back;
  int write_error, read_error;

  if (page <= 0)
    return 1;
  memory = mmap(NULL, 2 * page, PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (memory == MAP_FAILED)
    return 1;
  if (mprotect(memory + page, page, PROT_NONE))
    return 1;
  memcpy(memory + page - 4, "ABCD", 4);
  fd = open("/proc/lab4", O_RDWR);
  if (fd < 0)
    return 1;

  errno = 0;
  written = write(fd, memory + page - 4, 8);
  write_error = errno;
  errno = 0;
  read_back = read(fd, memory + page - 4, 8);
  read_error = errno;
  printf("write=%zd errno=%d; read=%zd errno=%d\n",
         written, write_error, read_back, read_error);
  close(fd);
  munmap(memory, 2 * page);
  return written != -1 || write_error != EFAULT ||
         read_back != -1 || read_error != EFAULT;
}
