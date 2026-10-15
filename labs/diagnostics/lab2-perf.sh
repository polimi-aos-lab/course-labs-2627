#!/bin/sh
# Run inside the AOS QEMU guest, not on the host.
set -eu
[ -e /dev/null ] || mknod /dev/null c 1 3
[ -d /sys/kernel/tracing/events ] || mount -t tracefs nodev /sys/kernel/tracing
mkdir -p /tmp
export PERF_PAGER=cat
printf '=== PERF VERSION ===\n'
perf --version
printf '=== PERF RECORD ===\n'
perf record -o /tmp/lab2-perf.data -c 1 \
  -e syscalls:sys_enter_openat -e syscalls:sys_exit_openat \
  -e syscalls:sys_enter_sendfile64 -e syscalls:sys_exit_sendfile64 \
  -- cat /init > /dev/null
printf '=== PERF SCRIPT ===\n'
perf script -i /tmp/lab2-perf.data > /tmp/lab2-perf-script.txt
cat /tmp/lab2-perf-script.txt
printf '=== PERF REPORT ===\n'
perf report -i /tmp/lab2-perf.data --stdio --sort comm --show-nr-samples --percent-limit 0 > /tmp/lab2-perf-report.txt
cat /tmp/lab2-perf-report.txt
printf '=== PERF DONE ===\n'
