---
title: "Lab 1 — Kernel development and debugging"
author: Vittorio Zaccaria
course: Advanced Operating Systems
institute: Politecnico di Milano
---

# Introduction to the environment
## This repo organization

A few words on the organisation of this repo. Where we get the kernel from, what is a [initramfs](https://en.wikipedia.org/wiki/Initial_ramdisk) (hint: initramfs is used as the first root filesystem that your machine has access to) and what you can produce with it. Our machine will not need another disk; this initial file system is everything we need to play with the kernel.

> Initramfs is setup using [busybox: The Swiss Army Knife of Embedded Linux](https://busybox.net/about.html)

## Building the development environment

Build the supported amd64 full image once from the repository root:

```bash
T=amd64 E=full make build-container
```

Then choose either frontend. Both edit the same bind-mounted repository and use
the same kernel, module build, initramfs, and QEMU.

### Host terminal and LazyVim

```bash
T=amd64 E=full make dev-up
T=amd64 E=full make dev-build
T=amd64 E=full make dev-vi F=modules/lab-1-intro-hello-module/module.c
```

The full image provides LazyVim and clangd. Exit LazyVim with `:qa`.

### Browser editor

```bash
make vscode-build-container
make vscode-up
```

Open `http://127.0.0.1:8080`, enter the password `aos-linux-labs`, and open
`modules/lab-1-intro-hello-module/module.c` from the Explorer. VS Code edits the
host repository at `/repo`; clangd diagnostics and navigation run inside the
container. If port 8080 is already in use, start it with
`make VSCODE_PORT=8081 vscode-up` and open that port instead.

## Running and rebuilding

With the host-terminal frontend, rebuild and start the generated kernel and
initramfs with:

```bash
T=amd64 E=full make dev-build
T=amd64 E=full make dev-run
```

With the browser frontend, use **Terminal → Run Build Task** for
`AOS: Build modules and initramfs`. Then use **Terminal → Run Task** and select
`AOS: Run QEMU (1 vCPU)`. The task terminal is the QEMU guest console. Whenever
you change a module, run the build task again before booting.

# Modules
## Modules and module lifecycle

- Modules are a **flexible way of handling** the operating system **image** at runtime.
- Instead of rebooting with a different operating system image, modules allow easy extension of the operating systems\' capabilities as required.
- It is the most convenient way with which we are going to play with the kernel.

See [lab-1-intro-hello-module](../modules/lab-1-intro-hello-module)

## Module parameters

- Parameters can be declared and initialised in code

```c
static int num = 5;
/* S_IRUG0: everyone can read the sysfs entry */
module_param(num, int, S_IRUG0);
```

- And defined at module instantiation time

```bash
insmod yourmodule.ko num=10
```

## Who executes the module?

**Loading a module does not create a process.** Who calls its initialization and cleanup functions?

The hello module logs the current task in both functions:

```c
#include <linux/sched.h>

/* Inside hello_init(): */
pr_info("hello_init: comm=%s pid=%d\n",
        current->comm, task_pid_nr(current));

/* Inside hello_cleanup(): */
pr_info("hello_cleanup: comm=%s pid=%d\n",
        current->comm, task_pid_nr(current));
```

`current` identifies the task executing this kernel code; `comm` is its name.

# Module debugging
## Kernel failures > an error return is not an oops

**An expected failure is handled through normal control flow. A programming defect can instead make kernel execution invalid.**

```tikz
\begin{document}
\begin{tikzpicture}[>=stealth, every node/.style={font=\sffamily\small},
  box/.style={draw,align=center,minimum width=3.4cm,minimum height=1cm}]
\node[box] (alloc) at (0,0) {Allocation fails:\\\texttt{kmalloc()} returns \texttt{NULL}};
\node[box] (handled) at (6,0) {Caller checks the result,\\cleans up and\\returns an error};
\node[box] (access) at (0,-2.4) {Code dereferences\\a null pointer};
\node[box] (fault) at (6,-2.4) {CPU raises an exception\\on the invalid access};
\draw[->,thick] (alloc) -- node[above] {handled failure} (handled);
\draw[->,thick] (access) -- node[above] {execution error} (fault);
\end{tikzpicture}
\end{document}
```
{.width=70% .center}

A failed allocation can lead to the second case if the caller dereferences the null result instead of checking it.

Not every invalid access is detected immediately: a write to mapped memory may silently corrupt another object.

## Kernel failures > what is an oops?

**An oops is Linux's handling of a serious kernel execution error when it cannot recover the failing execution path.** It produces a diagnostic report and abandons that path.

```tikz
\begin{document}
\begin{tikzpicture}[>=stealth, every node/.style={font=\sffamily\small},
  box/.style={draw,align=center,minimum width=3cm,minimum height=1cm}]
\node[box] (access) at (0,0) {Kernel code\\accesses \texttt{NULL}};
\node[box] (exception) at (4.5,0) {CPU exception:\\invalid access};
\node[box] (oops) at (9,0) {Oops:\\diagnostic report};
\draw[->,thick] (access) -- (exception);
\draw[->,thick] (exception) -- node[above,align=center,font=\scriptsize]
  {no recovery} (oops);
\end{tikzpicture}
\end{document}
```
{.width=85% .center}

- The **CPU exception** is the hardware event; the **oops** is the kernel's error handling and report.
- The report identifies the failing instruction, relevant registers and call trace.
- An oops does **not** by itself mean that the whole system has stopped or rebooted.

Some kernel exceptions have recovery paths. For example, supported user-memory access helpers can handle invalid user addresses; those faults need not cause an oops.

## Kernel failures > when does an oops lead to panic?

**Panic means that the kernel stops normal system-wide execution.** Whether an oops leads to panic depends on context and policy.

```tikz
\begin{document}
\begin{tikzpicture}[>=stealth, every node/.style={font=\sffamily\small},
  box/.style={draw,align=center,minimum width=3.5cm,minimum height=1cm}]
\node[box] (oops) at (0,0) {Oops:\\failing execution path\\cannot continue};
\node[box] (task) at (7,1.5) {Terminate the task;\\attempt to continue\\the rest of the system};
\node[box] (panic) at (7,-1.5) {Panic:\\stop normal execution\\of the whole system};
\draw[->,thick] (oops.north) |- node[pos=0.7,above,align=center,font=\scriptsize]
  {task context permits containment\\and policy permits continuation} (task.west);
\draw[->,thick] (oops.south) |- node[pos=0.7,below,align=center,font=\scriptsize]
  {fatal context, or\\\texttt{panic\_on\_oops=1}} (panic.west);
\end{tikzpicture}
\end{document}
```
{.width=60% .center}

If the error occurs while servicing an interrupt, the kernel cannot simply terminate a calling user task to contain it.

Continuing after an oops does not guarantee consistent state. After a panic, configuration determines crash dumping, halting or rebooting. Code can also call `panic()` directly, without a preceding oops.

## Kernel failures > reading the oops report

Real QEMU capture: Linux `5.16.0-rc1`, temporary module writing through a null pointer.

```tikz
\begin{document}
\begin{tikzpicture}[>=stealth,
  report/.style={anchor=north west,align=left,font=\ttfamily\scriptsize},
  note/.style={anchor=west,align=left,font=\sffamily\scriptsize}]
\node[anchor=west,font=\sffamily\bfseries] at (0,0.65) {REPORT EXCERPT};
\node[anchor=west,font=\sffamily\bfseries] at (11,0.65) {INTERPRETATION};
\node[report] (error) at (0,0.35) {BUG: kernel NULL pointer dereference,\\
  address: 0000000000000000\\
  \#PF: supervisor write access in kernel mode\\
  Oops: 0002 [\#1] PREEMPT SMP NOPTI};
\node[note] at (11,-0.15) {\textbf{Error and address}\\A kernel-mode write to address zero.\\\texttt{\#PF} means page fault.};
\draw[->] (9.7,-0.15) -- (10.7,-0.15);
\node[report] at (0,-1.15) {CPU: 0 PID: 77 Comm: insmod\\
  Tainted: G           O      5.16.0-rc1 \#1};
\node[note] at (11,-1.35) {\textbf{Execution environment}\\CPU, task, kernel version and taint.};
\draw[->] (9.7,-1.35) -- (10.7,-1.35);
\node[report] at (0,-2.15) {RIP: 0010:oops\_demo\_init+0x5/0x1000\\
  \space [oops\_demo]};
\node[note] at (11,-2.35) {\textbf{Failing instruction}\\\texttt{RIP}: function + byte offset,\\then the containing module.};
\draw[->] (9.7,-2.35) -- (10.7,-2.35);
\node[report] at (0,-3.15) {RSP: 0018:ffffc900001d7cb0 EFLAGS: 00000246\\
  RAX: 0000000000000000 RBX: 0000000000000000\\
  RCX: 0000000000000000};
\node[note] at (11,-3.5) {\textbf{Register state}\\Stack pointer, flags and data registers.\\Decode the instruction before\\assigning a meaning to each value.};
\draw[->] (9.7,-3.5) -- (10.7,-3.5);
\node[report] at (0,-4.5) {Call Trace:\\
  \space <TASK>\\
  \space do\_one\_initcall+0x44/0x200\\
  \space [...]\\
  \space load\_module+0x2381/0x26b0\\
  \space [...]};
\node[note] at (11,-5.05) {\textbf{Call path}\\Module initialization was reached\\through the module loader.};
\draw[->] (9.7,-5.05) -- (10.7,-5.05);
\node[report] at (0,-6.2) {Modules linked in: oops\_demo(O+)};
\node[note] at (11,-6.35) {\textbf{Module state}\\\texttt{O}: out-of-tree; \texttt{+}: being loaded.};
\draw[->] (9.7,-6.35) -- (10.7,-6.35);
\end{tikzpicture}
\end{document}
```
{.width=75% .center}

Excerpt: timestamps removed; lines selected and wrapped. `[...]` omits frames. [Full report](diagnostics/oops-demo.log).

## Poorman's printk

Printing from kernel to the log buffer is done today with the `pr_*()` family of functions:

- `pr_emerg(), pr_alert(), pr_crit(), pr_err(), pr_warn(), pr_notice(), pr_info(), pr_cont()`,

For example: `pr_info("Booting CPU %d\n", cpu);`

For pointers:

- `%p`: Display the hashed value of pointer by default.
- `%px`: Always display the address of a pointer (use carefully on non-sensitive addresses).
- `%pK`: Display hashed pointer value, zeros or the pointer address depending on kptr_restrict sysctl value

See for example
- [How to get printk format specifiers right — The Linux Kernel documentation](https://www.kernel.org/doc/html/latest/core-api/printk-formats.html)
- [bootlin.com/doc/training/debugging/debugging-slides.pdf](https://bootlin.com/doc/training/debugging/debugging-slides.pdf)

## The hard truth about kernel debugging

- Usually no magic formula, requires **creative detective work**
- This lab is not about this creative part (this requires time) but the tools that are available to you
- In general many ways in which you can arrive to the same result

# Introduction to GDB
## Introduction

Why use live GDB

- Understanding the code flow
- Dumping data structures and assembly
- Debugging hangs

Why not use live gdb

- Issue is not reproducible
- Don't know what to look for

## Including debug info in your kernel

You must use `CONFIG_DEBUG_INFO` in your `.config` file otherwise..

```
(gdb) c
Continuing.
^C
Thread 1 received signal SIGINT, Interrupt.
Oxffffffff81e8ccbf in default_idle ()
(gdb) bt
#0 ﻿﻿﻿Oxffffffff81e8ccbf in default_idle () <----- No line info!
#1 ﻿﻿﻿Oxffffffff81e8cf8c in default_idle_call()
#2 Oxffffffff810da469 in do_idle ()
```

## Disabling KSLR

You must boot with `nokaslr` your kernel otherwise you'll get random and unintelligible stack frame info

```
(gdb) c
Continuing.
^C
Thread 1 received signal SIGINT, Interrupt.
Oxffffffff81e8ccbf in ??
(gdb) bt
#0 ﻿﻿﻿Oxffffffff81e8ccbf in ?? <----- No symbol info!
#1 ﻿﻿﻿Oxffffffff81e8cf8c in ??
#2 Oxffffffff810da469 in ??
```

## External hardware > KGDB

The execution of the kernel can be fully controlled by gdb from another machine, connected through a serial line (enabled by `CONFIG_KGDB_SERIAL_CONSOLE`).
![](Images/lab%201%202024-05-14%2015.13.44.excalidraw.png){.width=80% .center}

%%[Edit in Excalidraw](Images/lab%201%202024-05-14%2015.13.44.excalidraw.md)%%

> GDB connected over a serial port to a live Linux machine.

It can do almost everything, including inserting breakpoints in interrupt handlers and provides GDB python scripts to ease debugging.

##  External hardware > JTAG

![](Images/lab%201%202024-05-14%2015.26.15.excalidraw.png){.width=75% .center}

%%[Edit in Excalidraw](Images/lab%201%202024-05-14%2015.26.15.excalidraw.md)%%

> GDB connected through JTAG to a live Linux machine; KGDB is not required.

JTAG is allows to debug a system with almost no functioning software. You use JTAG on system bring up if you are not sure that you even reach a point where kgdb could work.



## Internal emulation > QEMU

![](Images/lab%201%202024-05-15%2017.20.09.excalidraw.png){.width=85% .center}

%%[Edit in Excalidraw](Images/lab%201%202024-05-15%2017.20.09.excalidraw.md)%%

> GDB connected directly to QEMU; no intermediary is required.

With QEMU, we could emulate access to our linux system as it was over a jtag, even if kgdb is not enabled. GDB commands are the same though.

# Mini tutorial on GDB for the kernel

## Preliminaries > GDB commands > most used

```bash
break <sym> # inserts a break point
info break  # shows breakpoints
delete <num># deletes <num> breakpoint
continue    # continues from a breakpoint to the next
step        # enters the subroutine and breaks
next        # does not enter subroutines and breaks
bt          # prints stack backtrace
```

## Preliminaries > GDB commands > Linux specific scripts

```bash
lx-lsmod # list modules
lx-ps    # list processes
apropos lx

p $lx_current()
p *(struct task_struct *) <address of process from lx-ps>
p $container_of(listheadp, "struct <type x>", "name of the list head in <type ⨉")
p $lx_task_by_pid(<PID>)
set $t = $lx_task_by_pid(<PID>)
p $t -> __state # print state

```

## Anatomy of a syscall > attach to the running guest

Already at the amd64 QEMU shell; the hello module is built but **not loaded**.

This walkthrough uses terminal GDB. With the browser frontend, use the graphical
kernel and module debugging procedure near the end of this handout instead.

::::div{.columns}
:::div{.column width="50%"}
**QEMU monitor:** press `Ctrl-]`, then `c`.

```text
gdbserver tcp:127.0.0.1:1234
```

Use the same keys to return to the guest console.

**Second host terminal: `make dev-sh`, then**

```sh
cd /sources/linux
make scripts_gdb
gdb -q \
  -iex "add-auto-load-safe-path $PWD" \
  vmlinux
```
:::
:::div{.column width="50%"}
**GDB**

```gdb
set pagination off
target remote 127.0.0.1:1234
p sys_call_table[175]
hbreak __x64_sys_init_module
hbreak do_init_module
continue
```

On x86-64, **175** is `init_module`.

**Now run in the QEMU guest**

```sh
insmod /modules/lab-1-intro-hello-module.ko num=7
```

GDB stops before the syscall executes.
:::
::::

## Anatomy of a syscall > caller and arguments

At `__x64_sys_init_module`, `regs` points to the **user registers saved at syscall entry**, not GDB's current CPU registers.

::::div{.columns}
:::div{.column width="50%"}
**GDB at the first breakpoint**

```gdb
p $lx_current()->pid
p $lx_current()->comm
p regs->orig_ax
p/x regs->di
p/d regs->si
x/s regs->dx
x/4bx regs->di
```

The syscall arguments are:

```c
init_module(image, length, parameters)
```

`di`: image pointer; `si`: length in bytes; `dx`: parameter-string pointer.
:::
:::div{.column width="50%"}
**Observed in the remote run**

```text
pid:       80
comm:      "insmod..."
orig_ax:   175
di:        0x7fb6044fd010
si:        228288
string:    " \"num=7\""
ELF bytes: 0x7f 0x45 0x4c 0x46
```

PID, addresses and image length vary. The string includes BusyBox's added spaces and quotes.

The four bytes identify an **ELF image**. The task remains `insmod` while executing kernel code.
:::
::::

## Anatomy of a syscall > initialization and return

::::div{.columns}
:::div{.column width="50%"}
**GDB**

```gdb
continue
p mod->name
bt
finish
finish
finish
p/d $rax
detach
quit
```

At `do_init_module`, `mod->name` is `"module"`.

On this build, the three `finish` commands return from `do_init_module`, `load_module`, then `__do_sys_init_module`.
:::
:::div{.column width="50%"}
**Observed call path** — selected frames:

```text
do_init_module
load_module
__do_sys_init_module
do_syscall_x64
do_syscall_64
entry_SYSCALL_64
```

Each `finish` returned **0**; `$rax` was **0** at the syscall return to `do_syscall_x64`.

**Guest after detach:** status `0`, module `Live`.

```sh
echo $?
cat /proc/modules
rmmod module
```
:::
::::

## Timer callback > stop before it runs

After the syscall exercise, use a **fresh guest and a fresh GDB session**. The timer module must already be built into the initramfs.

::::div{.columns}
:::div{.column width="50%"}
**Reuse the monitor and GDB startup commands** from the syscall slide. In GDB:

```gdb
set pagination off
target remote 127.0.0.1:1234
hbreak do_init_module
continue
```

**Guest**

```sh
insmod /modules/lab-1-list-manip.ko
```

GDB stops before module initialization. The timer has not been armed yet.
:::
:::div{.column width="50%"}
**GDB at `do_init_module`**

```gdb
p mod->name
p $lx_current()->comm
lx-symbols /repo/modules/lab-1-list-manip
p/x &my_timer_handler
hbreak *my_timer_handler
continue
```

Observed: module `"module"`, task `"insmod"`.

The `*` selects the function's **entry address**, before its body executes. Install this breakpoint before continuing; the timer's three-second delay is not setup time.
:::
::::

## Timer callback > who is executing now?

::::div{.columns}
:::div{.column width="50%"}
**At the first callback entry**

```gdb
bt
p $lx_current()->pid
p $lx_current()->comm
x/i $pc
p timer
p/x timer->function
```

Observed PID **0**, name **`swapper/0`**.
`timer->function` matched the breakpoint address.

`current` identifies the interrupted task. It does not mean that task requested the callback; a different run may interrupt another task.
:::
:::div{.column width="50%"}
**Observed stack** — selected frames:

```text
my_timer_handler
__run_hrtimer
__hrtimer_run_queues
hrtimer_interrupt
__sysvec_apic_timer_interrupt
sysvec_apic_timer_interrupt
```

Unlike the syscall path, this callback is entered from a timer interrupt. GDB stopped unwinding at the interrupt-stack boundary in this run.

**End the demonstration here.** Exit QEMU with `Ctrl-]`, then `x`; then `quit` GDB.
Do not `continue`, `detach` or `rmmod` in this demonstration: the callback still contains the intentional list-traversal fault.
:::
::::

## Optional > debugging the list fault

The separate list-debugging exercise starts from a fresh VM. It is not needed to demonstrate timer execution context.

![](Images/lab-1%202024-09-25%2021.35.19.excalidraw.png){.width=85% .center}

%%[Edit in Excalidraw](Images/lab-1%202024-09-25%2021.35.19.excalidraw.md)%%

After removing the tail, `cur` stays unchanged and `cur->next` is null. The next loop iteration evaluates `cur->next->next`.

The callback allocates with `GFP_ATOMIC` and skips traversal if allocation fails; initialization uses `GFP_KERNEL` and frees any partial list on failure. Cleanup cancels the timer before freeing the list. The traversal fault remains intentional: do not treat this as a correct list implementation.

## Optional > post-fault analysis with GDB

After the panic, GDB attaches to QEMU at the panic path, not at the faulting instruction. The original `struct pt_regs` is still available through the `regs` parameter of the `page_fault_oops` frame:

```gdb
target remote 127.0.0.1:1234
lx-symbols /repo/modules/lab-1-list-manip
bt
frame N                    # select page_fault_oops; N varies
set $fault = regs
info line *$fault->ip
x/8i $fault->ip-16
p/x $fault->di
p *(struct list_node *)$fault->bx
p/x &head                  # address of the global variable
p/x head                   # pointer to the first node
p *head                    # first node
```

In the source, `head` is the global `struct list_node *head`; `lx-symbols` gives GDB its name and type. In the verified run, saved `RDI` was zero. On x86, `CR2` contains the virtual address that caused the latest page fault: the `next` field is at offset 8, so `0x8(%rdi)` with `RDI=0` explains `CR2=8`. `CR2` is not the page-fault error code. The disassembly showed that saved `RBX` held `cur`; inspecting it recovered `cur->next == NULL`. Confirm the compiler's register assignment from the disassembly before interpreting a saved register.

## Optional > graphical kernel and module debug in the browser

With the browser frontend running, first execute the
`AOS: Build modules and initramfs` task. Then:

1. run the `AOS: Debug QEMU (4 vCPUs)` task;
2. open **Run and Debug**, select `AOS: Attach to QEMU kernel`, and press `F5`;
3. inspect the stopped `start_kernel` frame, then press `F5` again to continue
   booting.

To stop in the hello module initialization, enter these commands in the Debug
Console before loading the module:

```gdb
aos-module-symbols /repo/modules/lab-1-intro-hello-module
break hello_init
```

Continue the kernel, then run
`insmod /modules/lab-1-intro-hello-module.ko` in the QEMU guest. The helper
resolves the module's runtime section addresses before `hello_init` executes.
GDB, QEMU, and the source tree all remain inside the browser container; no
separate `gdbfrontend` process or host GDB port is required.


## Linkography

- [Kernel debugging with QEMU](https://bmeneg.com/post/kernel-debugging-with-qemu/)
- [Provoking crashes with LKDTM](https://docs.kernel.org/fault-injection/provoke-crashes.html)
- [Linux kernel debugging](https://blog.k3170makan.com/2020/11/linux-kernel-exploitation-0x0-debugging.html)
- [Debugging the kernel using GDB](https://docs.kernel.org/dev-tools/gdb-kernel-debugging.html)
- [bootlin.com/doc/training/debugging/debugging-slides.pdf](https://bootlin.com/doc/training/debugging/debugging-slides.pdf)
- [Serial, KDB and KGDB debugging](https://elinux.org/images/1/1b/ELC19_Serial_kdb_kgdb.pdf)