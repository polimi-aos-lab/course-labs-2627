# AOS Linux Labs

Reproducible Linux-kernel development environment for the Advanced Operating
Systems course. Docker builds an amd64 Linux 5.16 kernel and a BusyBox
initramfs. Two frontends share the same containerized compiler, module build,
initramfs, and QEMU environment: a host-terminal workflow and a browser-based
VS Code workflow.

The public companion grows progressively. A checkout contains only the
infrastructure and laboratory material already released for the course.

## Prerequisites

- amd64 Linux with Docker Engine, or Intel/Apple-silicon macOS with Docker
  Desktop capable of running privileged `linux/amd64` containers;
- Git, GNU Make, a running Docker daemon, and outbound HTTPS access;
- at least 25 GiB free disk and 4 GiB RAM available to Docker;
- TCP port 1234 free.

The supported student configuration is `T=amd64 E=full`. Native Windows,
WSL2, and the experimental `aarch64` build are not supported.

## Repository layout

- `Dockerfile` and `scripts/`: container, kernel, and initramfs build;
- `modules/`: build infrastructure and currently released lab sources;
- `stage/`: QEMU launcher and locally generated kernel/initramfs artifacts.

The public companion may ship prebuilt boot artifacts. Local module products,
compile databases, and rebuilt images are intentionally not versioned.

## Choose an interaction mode

Two modes are currently available:

1. **Terminal workflow — reference mode.** Interact with the development
   container through the `make dev-*` commands and edit with LazyVim. This is
   the established and recommended fallback.
2. **Browser workflow — simpler, experimental mode.** Edit, build, run QEMU,
   and debug from a VS Code interface in the browser. It reduces terminal
   interaction, but it still requires broader testing on student machines. If
   it causes problems, return to the terminal workflow; both modes operate on
   the same repository files.

## Terminal workflow: build the environment

From a fresh clone:

```sh
T=amd64 E=full make build-container
T=amd64 E=full make dev-up
T=amd64 E=full make dev-build
```

`dev-build` must create non-empty files:

```text
stage/bzImage-amd64
stage/initramfs-busybox-amd64.cpio.gz
```

### Open a released source file

The full image includes LazyVim and clangd. `dev-build` creates a
`compile_commands.json` in each released module directory.

```sh
T=amd64 E=full make dev-vi F=modules/lab-1-intro-hello-module/module.c
```

Replace `scripts/init` with a released lab source path when directed by its
handout. Exit LazyVim with `:qa`.

## Browser workflow (experimental)

The browser workflow runs code-server, clangd, the build tools, and QEMU in a
separate container. It is usually the simpler interface, but remains under
validation. Build the shared base image, build the browser image, and start it:

```sh
make build-container
make vscode-build-container
make vscode-up
```

Open <http://127.0.0.1:8080> and use the password `aos-linux-labs`. The
workspace is `/repo`: edit files in the Explorer, use **Terminal → Run Build
Task** to rebuild modules and the initramfs, and use **Terminal → Run Task** to
boot QEMU with one or four vCPUs. These tasks execute inside the same container,
so no host compiler or editor integration is required after startup.
The service listens only on the host loopback interface. If port 8080 is busy
or you want a different local password, override both values when starting it:

```sh
make VSCODE_PORT=8081 VSCODE_PASSWORD='local-password' vscode-up
```

For graphical kernel debugging, run the `AOS: Debug QEMU (4 vCPUs)` task,
select `AOS: Attach to QEMU kernel` in the Run and Debug view, and press
<kbd>F5</kbd>. GDB attaches to QEMU's local stub and stops in
`start_kernel`; press <kbd>F5</kbd> again to continue booting.

To debug a loadable module, prepare its runtime symbols in the Debug Console
before `insmod`:

```gdb
aos-module-symbols /repo/modules/lab-1-intro-hello-module
break hello_init
```

Continue the kernel and load the matching `.ko` in the guest. The helper
intercepts `do_init_module`, relocates every allocated ELF section, and resolves
the pending source breakpoint before the module initialization runs.

Stop and remove the container with:

```sh
make vscode-down
```

## Start a module from the public hello-world example

`modules/lab-1-intro-hello-module` is always included as a minimal, complete
kernel-module example. Keep it unchanged as a reference and copy it when you
need a new module scaffold:

```sh
cp -Rf modules/lab-1-intro-hello-module modules/lab-my-module
```

Edit `modules/lab-my-module/module.c`. `make dev-build` in terminal mode, or
`AOS: Build modules and initramfs` in browser mode, automatically discovers the
new `lab-*` directory and installs `/modules/lab-my-module.ko` in the guest.


## Prepare the Lab 3 workspace

Lab 3 provides a complete atomic-counter warm-up and an intentionally
unsynchronized list scaffold. Keep the released scaffold unchanged and work on
a copy:

```sh
rm -rf modules/lab-3-th-list-work
cp -Rf modules/lab-3-th-rcu-scaffold modules/lab-3-th-list-work
```

The instructor will identify the exact synchronization changes at each
checkpoint. `make dev-build` automatically discovers the working directory and
installs `/modules/lab-3-th-list-work.ko` in the guest.

## Run the kernel

```sh
T=amd64 E=full make dev-run
```

A successful boot prints `Welcome to aos-mini-linux` and opens a BusyBox
shell. `uname -r` should report `5.16.0-rc1`. Exit QEMU with
<kbd>Ctrl-]</kbd>, then <kbd>x</kbd>.

## Clean up

```sh
T=amd64 E=full make dev-down
```
