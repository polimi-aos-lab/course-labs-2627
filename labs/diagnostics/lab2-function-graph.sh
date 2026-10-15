#!/bin/sh
# Run inside the AOS QEMU guest, not on the host.
set -eu
[ -e /dev/null ] || mknod /dev/null c 1 3
[ -d /sys/kernel/tracing/events ] || mount -t tracefs nodev /sys/kernel/tracing
# Linux 5.16 exposes function-graph controls in the top-level tracefs instance.
T=/sys/kernel/tracing
export T
echo 0 > "$T/tracing_on"
echo 0 > "$T/events/enable"
echo > "$T/set_event_pid"
echo nop > "$T/current_tracer"
echo > "$T/set_ftrace_filter"
echo do_sendfile > "$T/set_graph_function"
echo 3 > "$T/max_graph_depth"
echo function_graph > "$T/current_tracer"
echo > "$T/trace"
sh -c 'echo $$ > "$T/set_ftrace_pid"; echo 1 > "$T/tracing_on"; exec cat /init' > /dev/null
echo 0 > "$T/tracing_on"
printf '=== FUNCTION GRAPH ===\n'
cat "$T/trace"
printf '=== GRAPH BUFFER STATISTICS ===\n'
cat "$T/per_cpu/cpu0/stats"
echo nop > "$T/current_tracer"
echo > "$T/set_ftrace_pid"
echo > "$T/set_graph_function"
echo 0 > "$T/max_graph_depth"
printf '=== GRAPH DONE ===\n'
