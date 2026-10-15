#!/bin/sh
# Run inside a fresh AOS QEMU guest, not on the host.
set -eu
[ -e /dev/null ] || mknod /dev/null c 1 3
[ -d /sys/kernel/tracing/events ] || mount -t tracefs nodev /sys/kernel/tracing
mkdir -p /sys/kernel/tracing/instances/lab2
T=/sys/kernel/tracing/instances/lab2
export T
echo 0 > "$T/tracing_on"
echo nop > "$T/current_tracer"
echo 0 > "$T/events/enable"
echo > "$T/trace"
echo 1 > "$T/events/syscalls/sys_enter_openat/enable"
echo 1 > "$T/events/syscalls/sys_exit_openat/enable"
echo 1 > "$T/events/syscalls/sys_enter_read/enable"
echo 1 > "$T/events/syscalls/sys_exit_read/enable"
echo 1 > "$T/events/syscalls/sys_enter_sendfile64/enable"
echo 1 > "$T/events/syscalls/sys_exit_sendfile64/enable"
printf '=== SYSCALL EVENT FORMAT ===\n'
cat "$T/events/syscalls/sys_enter_sendfile64/format"
printf '=== WORKLOAD FILE SIZE ===\n'
wc -c /init
sh -c 'echo $$ > "$T/set_event_pid"; echo 1 > "$T/tracing_on"; exec cat /init' > /dev/null
echo 0 > "$T/tracing_on"
printf '=== SYSCALL TRACE ===\n'
cat "$T/trace"
printf '=== BUFFER STATISTICS ===\n'
cat "$T/per_cpu/cpu0/stats"
echo 0 > "$T/events/enable"
echo > "$T/set_event_pid"
printf '=== SYSCALL DONE ===\n'
